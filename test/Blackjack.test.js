const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Blackjack", function () {
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
        
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await (await HouseTreasury.deploy()).waitForDeployment();
        
        Blackjack = await ethers.getContractFactory("Blackjack");
        blackjack = await (await Blackjack.deploy(minBetAmount, treasury.getAddress())).waitForDeployment();
        
        await treasury.connect(owner).authorizeGame(await blackjack.getAddress());
        await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
        await blackjack.connect(owner).setActionCooldown(0);
    });

    describe("Betting Functions", function () {
        it("Should allow placing a bet", async function () {
            await blackjack.connect(addr1).placeBet();
            const playerHand = await blackjack.playerHands(addr1.address);
            expect(playerHand.bet).to.equal(minBetAmount);
            expect(playerHand.resolved).to.be.false;
        });

        it("Should reject bet without active account", async function () {
            await expect(
                blackjack.connect(addr2).placeBet()
            ).to.be.revertedWith("Insufficient balance or no active account");
        });
    });

    describe("Game Resolution", function () {
        beforeEach(async function () {
            await blackjack.connect(addr1).placeBet();
        });

        it("Should resolve winning hand correctly", async function () {
            const initialBalance = await treasury.playerBalances(addr1.address);
            await blackjack.connect(owner).resolveGames([addr1.address], [2]);
            const finalBalance = await treasury.playerBalances(addr1.address);
            expect(finalBalance).to.equal(initialBalance + (minBetAmount * BigInt(2)));
        });
    });
});