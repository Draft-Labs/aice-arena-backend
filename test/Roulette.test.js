const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Roulette", function () {
    let HouseTreasury;
    let Roulette;
    let treasury;
    let roulette;
    let owner;
    let addr1;
    let addr2;
    const minBetAmount = ethers.parseEther("0.01");

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await (await HouseTreasury.deploy()).waitForDeployment();
        
        Roulette = await ethers.getContractFactory("Roulette");
        roulette = await (await Roulette.deploy(minBetAmount, treasury.getAddress())).waitForDeployment();
        
        await treasury.connect(owner).authorizeGame(await roulette.getAddress());
        await treasury.connect(owner).fundHouseTreasury({ value: ethers.parseEther("100.0") });
        await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
        await roulette.connect(owner).setActionCooldown(0);
    });

    describe("Betting Functions", function () {
        it("Should allow placing a straight bet", async function () {
            await roulette.connect(addr1).placeBet(0, [17]);
            const bets = await roulette.getPlayerBets(addr1.address);
            expect(bets[0].betType).to.equal(0);
            expect(bets[0].amount).to.equal(minBetAmount);
        });

        it("Should reject bet without active account", async function () {
            await expect(
                roulette.connect(addr2).placeBet(0, [17])
            ).to.be.revertedWith("Insufficient balance or no active account");
        });
    });

    describe("Spin Resolution", function () {
        beforeEach(async function () {
            await roulette.connect(addr1).placeBet(0, [17]);
        });

        it("Should resolve winning straight bet correctly", async function () {
            const initialBalance = await treasury.playerBalances(addr1.address);
            await roulette.connect(owner).spin(17);
            const finalBalance = await treasury.playerBalances(addr1.address);
            expect(finalBalance).to.equal(initialBalance + (minBetAmount * BigInt(36)));
        });
    });
});