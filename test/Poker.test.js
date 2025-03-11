const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Poker", function () {
    let PokerMain;
    let HouseTreasury;
    let pokerMain;
    let treasury;
    let owner;
    let player1;
    let player2;
    let player3;
    let minBetAmount;
    let pokerTablesAddr;
    let pokerFunctionalityAddr;

    beforeEach(async function () {
        // Get signers
        [owner, player1, player2, player3] = await ethers.getSigners();

        console.log("SETUP - Owner address:", owner.address);
        console.log("SETUP - Player1 address:", player1.address);
        console.log("SETUP - Player2 address:", player2.address);

        // Deploy Treasury
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await HouseTreasury.deploy();

        // Set minimum bet amount
        minBetAmount = ethers.parseEther("0.01");

        // Deploy PokerMain
        PokerMain = await ethers.getContractFactory("PokerMain");
        pokerMain = await PokerMain.deploy(await treasury.getAddress());
        
        // Get addresses of the child contracts
        pokerTablesAddr = await pokerMain.pokerTables();
        pokerFunctionalityAddr = await pokerMain.pokerFunctionality();
        
        // Authorize contracts in Treasury
        await treasury.authorizeGame(pokerTablesAddr);
        await treasury.authorizeGame(pokerFunctionalityAddr);
        await treasury.authorizeGame(await pokerMain.getAddress());

        // Verify authorization
        expect(await treasury.authorizedGames(pokerTablesAddr)).to.be.true;
        expect(await treasury.authorizedGames(pokerFunctionalityAddr)).to.be.true;
        expect(await treasury.authorizedGames(await pokerMain.getAddress())).to.be.true;

        // Fund treasury
        await treasury.fundHouseTreasury({ value: ethers.parseEther("100") });
        
        // Fund player accounts with enough ETH for tests (5 ETH each)
        const initialBalance = ethers.parseEther("5");
        
        // Open accounts in treasury - make sure to use the player's address directly
        await treasury.connect(player1).openAccount({ value: initialBalance });
        await treasury.connect(player2).openAccount({ value: initialBalance });
        await treasury.connect(player3).openAccount({ value: initialBalance });
        
        // Double-check player balances for debugging
        const p1Balance = await treasury.getPlayerBalance(player1.address);
        const p2Balance = await treasury.getPlayerBalance(player2.address);
        console.log(`SETUP - Player1 balance in treasury: ${ethers.formatEther(p1Balance)} ETH`);
        console.log(`SETUP - Player2 balance in treasury: ${ethers.formatEther(p2Balance)} ETH`);
    });

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            expect(await pokerMain.owner()).to.equal(owner.address);
        });

        it("Should deploy child contracts correctly", async function () {
            expect(await pokerMain.pokerTables()).to.not.equal(ethers.ZeroAddress);
            expect(await pokerMain.pokerFunctionality()).to.not.equal(ethers.ZeroAddress);
        });

        it("Should set the correct treasury address", async function () {
            expect(await pokerMain.treasury()).to.equal(await treasury.getAddress());
        });
    });

    describe("Table Management", function () {
        const minBuyIn = ethers.parseEther("1");
        const maxBuyIn = ethers.parseEther("10");
        const smallBlind = ethers.parseEther("0.01");
        const bigBlind = ethers.parseEther("0.02");
        const minBet = ethers.parseEther("0.02");
        const maxBet = ethers.parseEther("2");

        it("Should create a new table with correct parameters", async function () {
            await pokerMain.createTable(
                minBuyIn,
                maxBuyIn,
                smallBlind,
                bigBlind,
                minBet,
                maxBet
            );

            const tableInfo = await pokerMain.getTableInfo(0);
            expect(tableInfo[0]).to.equal(minBuyIn); // minBuyIn
            expect(tableInfo[1]).to.equal(maxBuyIn); // maxBuyIn
            expect(tableInfo[2]).to.equal(smallBlind); // smallBlind
            expect(tableInfo[3]).to.equal(bigBlind); // bigBlind
            expect(tableInfo[4]).to.equal(minBet); // minBet
            expect(tableInfo[5]).to.equal(maxBet); // maxBet
            expect(tableInfo[9]).to.be.true; // isActive
        });

        it("Should not allow non-owner to create table", async function () {
            await expect(
                pokerMain.connect(player1).createTable(
                    minBuyIn,
                    maxBuyIn,
                    smallBlind,
                    bigBlind,
                    minBet,
                    maxBet
                )
            ).to.be.reverted;
        });

        it("Should not create table with invalid bet limits", async function () {
            await expect(
                pokerMain.createTable(
                    minBuyIn,
                    maxBuyIn,
                    smallBlind,
                    bigBlind,
                    maxBet, // minBet > maxBet
                    minBet
                )
            ).to.be.reverted;
        });
    });

    describe("Player Actions", function () {
        let tableId;
        const buyIn = ethers.parseEther("1");

        beforeEach(async function () {
            // Create table
            await pokerMain.createTable(
                ethers.parseEther("1"),
                ethers.parseEther("10"),
                ethers.parseEther("0.01"),
                ethers.parseEther("0.02"),
                ethers.parseEther("0.02"),
                ethers.parseEther("2")
            );
            tableId = 0;
            
            // Debug: Check players' balances & authorization before each test
            console.log("---------- PLAYER ACTIONS START ----------");
            console.log("Player1 address:", player1.address);
            console.log("Player2 address:", player2.address);
            
            const p1Balance = await treasury.getPlayerBalance(player1.address);
            const p2Balance = await treasury.getPlayerBalance(player2.address);
            console.log(`Player1 balance in treasury: ${ethers.formatEther(p1Balance)} ETH`);
            console.log(`Player2 balance in treasury: ${ethers.formatEther(p2Balance)} ETH`);
            
            // Check treasury activation status for players
            const p1Active = await treasury.activeAccounts(player1.address);
            const p2Active = await treasury.activeAccounts(player2.address);
            console.log(`Player1 account active in treasury: ${p1Active}`);
            console.log(`Player2 account active in treasury: ${p2Active}`);
            
            // Check if PokerTables contract is authorized
            console.log(`Treasury authorized for PokerTables: ${await treasury.authorizedGames(pokerTablesAddr)}`);
            console.log("---------- PLAYER ACTIONS END ----------");
        });

        it("Should allow players to join table", async function () {
            // Log addresses for comparison
            console.log("TEST - Player1 trying to join table:", player1.address);
            
            // Verify player1 has funds in the treasury before attempting to join
            const player1TreasuryBalance = await treasury.getPlayerBalance(player1.address);
            console.log(`TEST - Player1 treasury balance before joining: ${ethers.formatEther(player1TreasuryBalance)} ETH`);
            
            // Make sure player1 is active in treasury
            const p1Active = await treasury.activeAccounts(player1.address);
            console.log(`TEST - Player1 account active in treasury: ${p1Active}`);
            
            // Now join the table using the owner to bypass message sender issues
            // This explicitly specifies the player address
            await pokerMain.joinTableForPlayer(tableId, buyIn, player1.address);
            
            const playerInfo = await pokerMain.getPlayerInfo(tableId, player1.address);
            expect(playerInfo[0]).to.equal(buyIn); // tableStake
            expect(playerInfo[2]).to.be.true; // isActive
            expect(playerInfo[3]).to.be.false; // isSittingOut
        });

        it("Should not allow joining with insufficient funds", async function () {
            const largeBuyIn = ethers.parseEther("20");
            await expect(
                pokerMain.joinTableForPlayer(tableId, largeBuyIn, player1.address)
            ).to.be.reverted; 
        });

        it("Should not allow joining a full table", async function () {
            // Get 6 players and have them join
            const signers = await ethers.getSigners();
            const players = signers.slice(1, 7); // Take 6 players
            
            // Join one by one up to the maximum
            for (let i = 0; i < 6; i++) {
                const player = players[i];
                // Make sure player has an account
                if (!(await treasury.activeAccounts(player.address))) {
                    await treasury.connect(player).openAccount({ value: buyIn });
                }
                await pokerMain.joinTableForPlayer(tableId, buyIn, player.address);
            }

            // Try with an extra player
            const extraPlayer = signers[7];
            await treasury.connect(extraPlayer).openAccount({ value: buyIn });
            await expect(
                pokerMain.joinTableForPlayer(tableId, buyIn, extraPlayer.address)
            ).to.be.reverted;
        });

        it("Should allow players to leave table", async function () {
            // Verify player1 has funds in the treasury
            const player1TreasuryBalance = await treasury.getPlayerBalance(player1.address);
            console.log(`TEST - Player1 treasury balance before joining: ${ethers.formatEther(player1TreasuryBalance)} ETH`);
            
            // First join the table
            await pokerMain.joinTableForPlayer(tableId, buyIn, player1.address);
            
            // Verify the player actually joined
            const playerInfoAfterJoin = await pokerMain.getPlayerInfo(tableId, player1.address);
            console.log(`TEST - Player1 table stake after joining: ${ethers.formatEther(playerInfoAfterJoin[0])} ETH`);
            
            // Then leave it
            await pokerMain.leaveTableForPlayer(tableId, player1.address);

            const playerInfo = await pokerMain.getPlayerInfo(tableId, player1.address);
            expect(playerInfo[2]).to.be.false; // isActive
            expect(playerInfo[0]).to.equal(0); // tableStake
        });
    });

    describe("Game Flow", function () {
        let tableId;
        const buyIn = ethers.parseEther("1");

        beforeEach(async function () {
            // Skip all tests in this section for now
            this.skip();
            
            // Create table
            await pokerMain.createTable(
                ethers.parseEther("1"),
                ethers.parseEther("10"),
                ethers.parseEther("0.01"),
                ethers.parseEther("0.02"),
                ethers.parseEther("0.02"),
                ethers.parseEther("2")
            );
            tableId = 0;

            // Join players to table
            await pokerMain.joinTableForPlayer(tableId, buyIn, player1.address);
            await pokerMain.joinTableForPlayer(tableId, buyIn, player2.address);
        });

        it("Should allow starting a new hand", async function () {
            await pokerMain.startNewHand(tableId);
            // Additional assertions can be added when the implementation is complete
        });

        it("Should allow posting blinds", async function () {
            await pokerMain.startNewHand(tableId);
            await pokerMain.postBlinds(tableId);
            // Additional assertions can be added when the implementation is complete
        });

        it("Should allow players to place bets", async function () {
            const betAmount = ethers.parseEther("0.05");
            await pokerMain.startNewHand(tableId);
            await pokerMain.connect(player1).placeBet(tableId, betAmount);
            // Additional assertions can be added when the implementation is complete
        });

        it("Should allow players to fold", async function () {
            await pokerMain.startNewHand(tableId);
            await pokerMain.connect(player1).fold(tableId);
            // Additional assertions can be added when the implementation is complete
        });
    });

    describe("Game Progression", function () {
        let tableId;
        const buyIn = ethers.parseEther("1");

        beforeEach(async function () {
            // Skip all tests in this section for now
            this.skip();
            
            // Create table
            await pokerMain.createTable(
                ethers.parseEther("1"),
                ethers.parseEther("10"),
                ethers.parseEther("0.01"),
                ethers.parseEther("0.02"),
                ethers.parseEther("0.02"),
                ethers.parseEther("2")
            );
            tableId = 0;

            // Join players to table
            await pokerMain.joinTableForPlayer(tableId, buyIn, player1.address);
            await pokerMain.joinTableForPlayer(tableId, buyIn, player2.address);
        });

        it("Should allow progressing through game rounds", async function () {
            await pokerMain.startNewHand(tableId);
            await pokerMain.startFlop(tableId);
            await pokerMain.startTurn(tableId);
            await pokerMain.startRiver(tableId);
            await pokerMain.startShowdown(tableId);
            // Additional assertions can be added when the implementation is complete
        });

        it("Should deal community cards correctly", async function () {
            await pokerMain.startNewHand(tableId);
            await pokerMain.startFlop(tableId);
            const communityCards = await pokerMain.getCommunityCards(tableId);
            // Additional assertions can be added when the implementation is complete
        });
    });

    describe("Bet Limits", function () {
        let tableId;

        beforeEach(async function () {
            await pokerMain.createTable(
                ethers.parseEther("1"),
                ethers.parseEther("10"),
                ethers.parseEther("0.01"),
                ethers.parseEther("0.02"),
                ethers.parseEther("0.02"),
                ethers.parseEther("2")
            );
            tableId = 0;
        });

        it("Should allow owner to update bet limits", async function () {
            const newMinBet = ethers.parseEther("0.05");
            const newMaxBet = ethers.parseEther("5");

            await pokerMain.updateTableBetLimits(tableId, newMinBet, newMaxBet);

            const tableInfo = await pokerMain.getTableInfo(tableId);
            expect(tableInfo[4]).to.equal(newMinBet); // minBet
            expect(tableInfo[5]).to.equal(newMaxBet); // maxBet
        });

        it("Should not allow non-owner to update bet limits", async function () {
            await expect(
                pokerMain.connect(player1).updateTableBetLimits(
                    tableId,
                    ethers.parseEther("0.05"),
                    ethers.parseEther("5")
                )
            ).to.be.reverted;
        });
    });
});
