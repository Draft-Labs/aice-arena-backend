const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Poker", function () {
    let Poker;
    let HouseTreasury;
    let poker;
    let treasury;
    let owner;
    let player1;
    let player2;
    let player3;
    let minBetAmount;

    beforeEach(async function () {
        // Get signers
        [owner, player1, player2, player3] = await ethers.getSigners();

        // Deploy Treasury
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await HouseTreasury.deploy();

        // Set minimum bet amount
        minBetAmount = ethers.parseEther("0.01");

        // Deploy Poker
        Poker = await ethers.getContractFactory("Poker");
        poker = await Poker.deploy(minBetAmount, await treasury.getAddress());

        // Authorize Poker contract in Treasury
        await treasury.authorizeGame(await poker.getAddress());

        // Fund treasury
        await treasury.fundHouseTreasury({ value: ethers.parseEther("100") });
    });

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            expect(await poker.owner()).to.equal(owner.address);
        });

        it("Should set the correct minimum bet amount", async function () {
            expect(await poker.minBetAmount()).to.equal(minBetAmount);
        });

        it("Should set the correct treasury address", async function () {
            expect(await poker.treasury()).to.equal(await treasury.getAddress());
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
            await poker.createTable(
                minBuyIn,
                maxBuyIn,
                smallBlind,
                bigBlind,
                minBet,
                maxBet
            );

            const tableInfo = await poker.getTableInfo(0);
            expect(tableInfo.minBuyIn).to.equal(minBuyIn);
            expect(tableInfo.maxBuyIn).to.equal(maxBuyIn);
            expect(tableInfo.smallBlind).to.equal(smallBlind);
            expect(tableInfo.bigBlind).to.equal(bigBlind);
            expect(tableInfo.minBet).to.equal(minBet);
            expect(tableInfo.maxBet).to.equal(maxBet);
            expect(tableInfo.isActive).to.be.true;
        });

        it("Should not allow non-owner to create table", async function () {
            await expect(
                poker.connect(player1).createTable(
                    minBuyIn,
                    maxBuyIn,
                    smallBlind,
                    bigBlind,
                    minBet,
                    maxBet
                )
            ).to.be.revertedWithCustomError(poker, "OnlyOwnerAllowed");
        });

        it("Should not create table with invalid bet limits", async function () {
            await expect(
                poker.createTable(
                    minBuyIn,
                    maxBuyIn,
                    smallBlind,
                    bigBlind,
                    maxBet, // minBet > maxBet
                    minBet
                )
            ).to.be.revertedWithCustomError(poker, "InvalidBetLimits");
        });
    });

    describe("Player Actions", function () {
        let tableId;
        const buyIn = ethers.parseEther("1");

        beforeEach(async function () {
            // Create table
            await poker.createTable(
                ethers.parseEther("1"),
                ethers.parseEther("10"),
                ethers.parseEther("0.01"),
                ethers.parseEther("0.02"),
                ethers.parseEther("0.02"),
                ethers.parseEther("2")
            );
            tableId = 0;

            // Fund player accounts in treasury
            await treasury.connect(player1).openAccount({ value: buyIn });
            await treasury.connect(player2).openAccount({ value: buyIn });
        });

        it("Should allow players to join table", async function () {
            await poker.connect(player1).joinTable(tableId, buyIn);
            
            const playerInfo = await poker.getPlayerInfo(tableId, player1.address);
            expect(playerInfo.tableStake).to.equal(buyIn);
            expect(playerInfo.isActive).to.be.true;
            expect(playerInfo.isSittingOut).to.be.false;
        });

        it("Should not allow joining with insufficient funds", async function () {
            const largeBuyIn = ethers.parseEther("20");
            await expect(
                poker.connect(player1).joinTable(tableId, largeBuyIn)
            ).to.be.revertedWithCustomError(poker, "InvalidBuyIn");
        });

        it("Should not allow joining a full table", async function () {
            const signers = await ethers.getSigners();
            const players = signers.slice(1, 7);
            
            for (const player of players) {
                const isActive = await treasury.activeAccounts(player.address);
                if (!isActive) {
                    await treasury.connect(player).openAccount({ value: buyIn });
                }
                await poker.connect(player).joinTable(tableId, buyIn);
            }

            const extraPlayer = signers[7];
            await treasury.connect(extraPlayer).openAccount({ value: buyIn });
            await expect(
                poker.connect(extraPlayer).joinTable(tableId, buyIn)
            ).to.be.revertedWithCustomError(poker, "TableFull");
        });

        it("Should allow players to leave table", async function () {
            await poker.connect(player1).joinTable(tableId, buyIn);
            await poker.connect(player1).leaveTable(tableId);

            const playerInfo = await poker.getPlayerInfo(tableId, player1.address);
            expect(playerInfo.isActive).to.be.false;
            expect(playerInfo.tableStake).to.equal(0);
        });
    });

    describe("Game Flow", function () {
        // Add tests for game flow, betting rounds, etc.
        // This section will be expanded as more game logic is implemented
    });

    describe("Bet Limits", function () {
        let tableId;

        beforeEach(async function () {
            await poker.createTable(
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

            await poker.updateTableBetLimits(tableId, newMinBet, newMaxBet);

            const tableInfo = await poker.getTableInfo(tableId);
            expect(tableInfo.minBet).to.equal(newMinBet);
            expect(tableInfo.maxBet).to.equal(newMaxBet);
        });

        it("Should not allow non-owner to update bet limits", async function () {
            await expect(
                poker.connect(player1).updateTableBetLimits(
                    tableId,
                    ethers.parseEther("0.05"),
                    ethers.parseEther("5")
                )
            ).to.be.revertedWithCustomError(poker, "OnlyOwnerAllowed");
        });
    });
});
