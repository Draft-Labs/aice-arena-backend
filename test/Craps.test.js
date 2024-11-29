const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Craps", function () {
    let HouseTreasury;
    let Craps;
    let treasury;
    let craps;
    let owner;
    let addr1;
    let addr2;
    const minBetAmount = ethers.parseEther("0.01");

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await (await HouseTreasury.deploy()).waitForDeployment();
        
        Craps = await ethers.getContractFactory("Craps");
        craps = await (await Craps.deploy(minBetAmount, treasury.getAddress())).waitForDeployment();
        
        await treasury.connect(owner).authorizeGame(await craps.getAddress());
        await treasury.connect(owner).fundHouseTreasury({ value: ethers.parseEther("100.0") });
        await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
        await craps.connect(owner).setActionCooldown(0);
    });

    describe("Betting Functions", function () {
        it("Should allow placing a bet", async function () {
            await craps.connect(addr1).placeBet(0);
            const bet = await craps.playerBets(addr1.address, 0);
            expect(bet.amount).to.equal(minBetAmount);
            expect(bet.resolved).to.be.false;
        });

        it("Should reject bet without active account", async function () {
            await expect(
                craps.connect(addr2).placeBet(0)
            ).to.be.revertedWith("Insufficient balance or no active account");
        });
    });

    describe("Roll Resolution", function () {
        beforeEach(async function () {
            await craps.connect(addr1).placeBet(0);
        });

        it("Should resolve winning Pass Line bet", async function () {
            const initialBalance = await treasury.playerBalances(addr1.address);
            await craps.connect(owner).resolveRoll(7);
            const finalBalance = await treasury.playerBalances(addr1.address);
            expect(finalBalance).to.equal(initialBalance + (minBetAmount * BigInt(2)));
        });

        it("Should clear resolved bets", async function () {
            await craps.connect(owner).resolveRoll(7);
            const bet = await craps.playerBets(addr1.address, 0);
            expect(bet.amount).to.equal(0);
            expect(bet.resolved).to.be.true;
        });
    });
});