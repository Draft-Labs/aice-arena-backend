const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Poker Game", function () {
    let PokerTable, PokerBetting, PokerPlayerManager, PokerGameState, PokerTreasury, PokerHandEvaluator;
    let pokerTable, pokerBetting, pokerPlayerManager, pokerGameState, pokerTreasury;
    let owner, player1, player2, player3;
    let SMALL_BLIND, BIG_BLIND, MIN_BUY_IN, MAX_BUY_IN;

    beforeEach(async function () {
        [owner, player1, player2, player3] = await ethers.getSigners();

        // Set up constants using ethers
        SMALL_BLIND = ethers.parseEther("0.001");
        BIG_BLIND = ethers.parseEther("0.002");
        MIN_BUY_IN = ethers.parseEther("0.1");
        MAX_BUY_IN = ethers.parseEther("1.0");

        // Deploy contracts
        PokerTable = await ethers.getContractFactory("PokerTable");
        PokerBetting = await ethers.getContractFactory("PokerBetting");
        PokerPlayerManager = await ethers.getContractFactory("PokerPlayerManager");
        PokerGameState = await ethers.getContractFactory("PokerGameState");
        PokerTreasury = await ethers.getContractFactory("PokerTreasury");
        const HouseTreasury = await ethers.getContractFactory("HouseTreasury");

        // First deploy HouseTreasury
        const houseTreasury = await HouseTreasury.deploy();
        await houseTreasury.waitForDeployment();
        const houseTreasuryAddress = await houseTreasury.getAddress();

        // Deploy supporting contracts first
        pokerBetting = await PokerBetting.deploy(ethers.ZeroAddress, houseTreasuryAddress);
        pokerPlayerManager = await PokerPlayerManager.deploy(ethers.ZeroAddress);
        pokerGameState = await PokerGameState.deploy(ethers.ZeroAddress);
        pokerTreasury = await PokerTreasury.deploy(ethers.ZeroAddress, houseTreasuryAddress);

        // Wait for deployments
        await pokerBetting.waitForDeployment();
        await pokerPlayerManager.waitForDeployment();
        await pokerGameState.waitForDeployment();
        await pokerTreasury.waitForDeployment();

        // Get addresses
        const bettingAddress = await pokerBetting.getAddress();
        const playerManagerAddress = await pokerPlayerManager.getAddress();
        const gameStateAddress = await pokerGameState.getAddress();
        const treasuryAddress = await pokerTreasury.getAddress();

        // Deploy PokerTable with correct addresses
        pokerTable = await PokerTable.deploy(
            bettingAddress,
            playerManagerAddress,
            gameStateAddress,
            treasuryAddress
        );
        await pokerTable.waitForDeployment();
        const pokerTableAddress = await pokerTable.getAddress();

        // Update supporting contracts with PokerTable address
        await pokerBetting.setPokerTable(pokerTableAddress);
        await pokerPlayerManager.setPokerTable(pokerTableAddress);
        await pokerGameState.setPokerTable(pokerTableAddress);
        await pokerTreasury.setPokerTable(pokerTableAddress);

        // Authorize the poker contracts in HouseTreasury
        await houseTreasury.authorizeGame(pokerTableAddress);
        await houseTreasury.authorizeGame(bettingAddress);
        await houseTreasury.authorizeGame(treasuryAddress);
    });

    describe("Table Management", function () {
        it("Should create a new table with correct parameters", async function () {
            const tx = await pokerTable.createTable(MIN_BUY_IN, MAX_BUY_IN, SMALL_BLIND, BIG_BLIND);
            const receipt = await tx.wait();
            const event = receipt.logs.find(e => e.eventName === 'TableCreated');
            expect(event).to.not.be.undefined;
            expect(event.args.minBuyIn).to.equal(MIN_BUY_IN);
            expect(event.args.maxBuyIn).to.equal(MAX_BUY_IN);
        });

        it("Should allow players to join table", async function () {
            await pokerTable.createTable(MIN_BUY_IN, MAX_BUY_IN, SMALL_BLIND, BIG_BLIND);
            const buyIn = MIN_BUY_IN;
            
            await pokerPlayerManager.connect(player1).joinTable(0, buyIn, { value: buyIn });
            const playerInfo = await pokerTable.getPlayerInfo(0, player1.address);
            expect(playerInfo.isActive).to.be.true;
            expect(playerInfo.tableStake).to.equal(buyIn);
        });

        it("Should allow players to leave table", async function () {
            await pokerTable.createTable(MIN_BUY_IN, MAX_BUY_IN, SMALL_BLIND, BIG_BLIND);
            const buyIn = MIN_BUY_IN;
            
            await pokerPlayerManager.connect(player1).joinTable(0, buyIn, { value: buyIn });
            await pokerPlayerManager.connect(player1).leaveTable(0);
            
            const playerInfo = await pokerTable.getPlayerInfo(0, player1.address);
            expect(playerInfo.isActive).to.be.false;
        });
    });

    describe("Game Flow", function () {
        beforeEach(async function () {
            await pokerTable.createTable(MIN_BUY_IN, MAX_BUY_IN, SMALL_BLIND, BIG_BLIND);
            const buyIn = MIN_BUY_IN;
            await pokerPlayerManager.connect(player1).joinTable(0, buyIn, { value: buyIn });
            await pokerPlayerManager.connect(player2).joinTable(0, buyIn, { value: buyIn });
        });

        it("Should start game when enough players join", async function () {
            await pokerGameState.startGame(0);
            const tableInfo = await pokerTable.getTableInfo(0);
            expect(tableInfo.currentState).to.equal(2); // PreFlop
        });

        it("Should deal cards to players", async function () {
            await pokerGameState.startGame(0);
            await pokerGameState.dealHoleCards(0);
            
            const player1Cards = await pokerTable.getPlayerCards(0, player1.address);
            expect(player1Cards.holeCards.length).to.equal(2);
        });

        it("Should handle betting rounds", async function () {
            await pokerGameState.startGame(0);
            await pokerGameState.dealHoleCards(0);

            // Post blinds
            await pokerBetting.postBlinds(0);

            // Player1 (small blind) calls
            await pokerBetting.connect(player1).call(0);

            // Player2 (big blind) checks
            await pokerBetting.connect(player2).check(0);

            // Deal flop
            await pokerGameState.dealFlop(0);
            const communityCards = await pokerTable.getCommunityCards(0);
            expect(communityCards.length).to.equal(3);
        });
    });

    describe("Player Actions", function () {
        beforeEach(async function () {
            await pokerTable.createTable(MIN_BUY_IN, MAX_BUY_IN, SMALL_BLIND, BIG_BLIND);
            const buyIn = MIN_BUY_IN;
            await pokerPlayerManager.connect(player1).joinTable(0, buyIn, { value: buyIn });
            await pokerPlayerManager.connect(player2).joinTable(0, buyIn, { value: buyIn });
            await pokerGameState.startGame(0);
            await pokerGameState.dealHoleCards(0);
            await pokerBetting.postBlinds(0);
        });

        it("Should allow players to check when no bets", async function () {
            await pokerBetting.connect(player1).call(0);
            await pokerBetting.connect(player2).check(0);
            const tableInfo = await pokerTable.getTableInfo(0);
            expect(tableInfo.pot).to.equal(SMALL_BLIND + BIG_BLIND + (BIG_BLIND - SMALL_BLIND));
        });

        it("Should allow players to raise", async function () {
            const raiseAmount = BIG_BLIND * 2n;
            await pokerBetting.connect(player1).raise(0, raiseAmount);
            const tableInfo = await pokerTable.getTableInfo(0);
            expect(tableInfo.pot).to.be.gt(SMALL_BLIND + BIG_BLIND);
        });

        it("Should allow players to fold", async function () {
            await pokerBetting.connect(player1).fold(0);
            const player1Info = await pokerTable.getPlayerInfo(0, player1.address);
            expect(player1Info.inHand).to.be.false;
        });
    });

    describe("Game Progression", function () {
        beforeEach(async function () {
            await pokerTable.createTable(MIN_BUY_IN, MAX_BUY_IN, SMALL_BLIND, BIG_BLIND);
            const buyIn = MIN_BUY_IN;
            await pokerPlayerManager.connect(player1).joinTable(0, buyIn, { value: buyIn });
            await pokerPlayerManager.connect(player2).joinTable(0, buyIn, { value: buyIn });
            await pokerGameState.startGame(0);
        });

        it("Should progress through all game states", async function () {
            // PreFlop
            await pokerGameState.dealHoleCards(0);
            await pokerBetting.postBlinds(0);
            await pokerBetting.connect(player1).call(0);
            await pokerBetting.connect(player2).check(0);

            // Flop
            await pokerGameState.dealFlop(0);
            await pokerBetting.connect(player1).check(0);
            await pokerBetting.connect(player2).check(0);

            // Turn
            await pokerGameState.dealTurn(0);
            await pokerBetting.connect(player1).check(0);
            await pokerBetting.connect(player2).check(0);

            // River
            await pokerGameState.dealRiver(0);
            await pokerBetting.connect(player1).check(0);
            await pokerBetting.connect(player2).check(0);

            // Showdown
            await pokerGameState.startShowdown(0);
            const tableInfo = await pokerTable.getTableInfo(0);
            expect(tableInfo.currentState).to.equal(6); // Showdown
        });

        it("Should determine winner and award pot", async function () {
            await pokerGameState.dealHoleCards(0);
            await pokerBetting.postBlinds(0);
            await pokerBetting.connect(player1).call(0);
            await pokerBetting.connect(player2).check(0);

            // Progress to showdown
            await pokerGameState.dealFlop(0);
            await pokerGameState.dealTurn(0);
            await pokerGameState.dealRiver(0);
            await pokerGameState.startShowdown(0);

            // Determine winner
            await pokerGameState.determineWinner(0);
            const tableInfo = await pokerTable.getTableInfo(0);
            expect(tableInfo.pot).to.equal(0); // Pot should be awarded
        });
    });
});
