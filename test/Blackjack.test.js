const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Blackjack Game", function () {
    let HouseTreasury;
    let Blackjack;
    let treasury;
    let blackjack;
    let owner;
    let addr1;
    let addr2;
    const minBetAmount = ethers.parseEther("0.01");

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        
        // Deploy Treasury first
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await (await HouseTreasury.deploy()).waitForDeployment();
        
        // Deploy Blackjack with Treasury address
        Blackjack = await ethers.getContractFactory("Blackjack");
        blackjack = await (await Blackjack.deploy(minBetAmount, treasury.getAddress())).waitForDeployment();
        
        // Authorize Blackjack contract in Treasury
        await treasury.connect(owner).authorizeGame(await blackjack.getAddress());
        
        // Fund Treasury
        await treasury.connect(owner).fundTreasury({ value: ethers.parseEther("10.0") });
    });

    describe("Deployment", function () {
        it("Should set the correct owner", async function () {
            expect(await blackjack.owner()).to.equal(owner.address);
        });

        it("Should set the correct minimum bet", async function () {
            expect(await blackjack.minBetAmount()).to.equal(minBetAmount);
        });

        it("Should set the correct treasury address", async function () {
            expect(await blackjack.treasury()).to.equal(await treasury.getAddress());
        });
    });

    describe("Betting Functions", function () {
        it("Should allow placing a bet", async function () {
            await blackjack.connect(addr1).placeBet({ value: minBetAmount });
            const playerHand = await blackjack.playerHands(addr1.address);
            expect(playerHand.bet).to.equal(minBetAmount);
            expect(playerHand.resolved).to.be.false;
        });

        it("Should reject bet below minimum", async function () {
            await expect(
                blackjack.connect(addr1).placeBet({ value: ethers.parseEther("0.005") })
            ).to.be.revertedWith("Bet amount is below the minimum required.");
        });

        it("Should reject multiple active bets from same player", async function () {
            await blackjack.connect(addr1).placeBet({ value: minBetAmount });
            await expect(
                blackjack.connect(addr1).placeBet({ value: minBetAmount })
            ).to.be.revertedWith("Player already has an active bet.");
        });

        it("Should add player to active players list", async function () {
            await blackjack.connect(addr1).placeBet({ value: minBetAmount });
            const activePlayers = await blackjack.getActivePlayers();
            expect(activePlayers).to.include(addr1.address);
        });
    });

    describe("Game Resolution", function () {
        beforeEach(async function () {
            await blackjack.connect(addr1).placeBet({ value: minBetAmount });
            await blackjack.connect(addr2).placeBet({ value: minBetAmount });
        });

        it("Should resolve games correctly", async function () {
            const initialBalance = await ethers.provider.getBalance(addr1.address);
            await blackjack.connect(owner).resolveGames(
                [addr1.address],
                [2] // 2x multiplier
            );
            const finalBalance = await ethers.provider.getBalance(addr1.address);
            expect(finalBalance).to.be.closeTo(
                initialBalance + (minBetAmount * BigInt(2)),
                ethers.parseEther("0.001")
            );
        });

        it("Should clear all games after resolution", async function () {
            await blackjack.connect(owner).resolveGames(
                [addr1.address, addr2.address],
                [2, 2]
            );
            const activePlayers = await blackjack.getActivePlayers();
            expect(activePlayers.length).to.equal(0);
        });

        it("Should emit GameResolved events", async function () {
            await expect(blackjack.connect(owner).resolveGames(
                [addr1.address],
                [2]
            )).to.emit(blackjack, "GameResolved")
              .withArgs(addr1.address, minBetAmount * BigInt(2));
        });

        it("Should reject resolution with mismatched arrays", async function () {
            await expect(
                blackjack.connect(owner).resolveGames(
                    [addr1.address],
                    [2, 2]
                )
            ).to.be.revertedWith("Arrays length mismatch");
        });
    });

    describe("Access Control", function () {
        it("Should only allow owner to resolve games", async function () {
            await expect(
                blackjack.connect(addr1).resolveGames([], [])
            ).to.be.revertedWith("Only owner can call this function.");
        });
    });
});