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
        await treasury.connect(owner).fundTreasury({ value: ethers.parseEther("10.0") });
        await craps.connect(owner).setActionCooldown(0);
    });

    describe("Betting Functions", function () {
        it("Should allow placing a bet", async function () {
            await craps.connect(addr1).placeBet(0, { value: minBetAmount });
            const bet = await craps.playerBets(addr1.address, 0);
            expect(bet.amount).to.equal(minBetAmount);
            expect(bet.resolved).to.be.false;
        });

        it("Should add player to active players list", async function () {
            await craps.connect(addr1).placeBet(0, { value: minBetAmount });
            const activePlayers = await craps.getActivePlayers();
            expect(activePlayers).to.include(addr1.address);
        });

        it("Should reject multiple bets of same type", async function () {
            await craps.connect(addr1).placeBet(0, { value: minBetAmount });
            await expect(
                craps.connect(addr1).placeBet(0, { value: minBetAmount })
            ).to.be.revertedWith("Player already has an active bet of this type.");
        });
    });

    describe("Roll Resolution", function () {
        beforeEach(async function () {
            await craps.connect(addr1).placeBet(0, { value: minBetAmount }); // Pass Line bet
        });

        it("Should resolve winning Pass Line bet", async function () {
            const initialBalance = await ethers.provider.getBalance(addr1.address);
            await craps.connect(owner).resolveRoll(7);
            const finalBalance = await ethers.provider.getBalance(addr1.address);
            expect(finalBalance).to.be.closeTo(
                initialBalance + (minBetAmount * BigInt(2)),
                ethers.parseEther("0.001")
            );
        });

        it("Should update game phase on point numbers", async function () {
            await craps.connect(owner).resolveRoll(4);
            expect(await craps.currentPhase()).to.equal(1); // Come phase
            expect(await craps.point()).to.equal(4);
        });

        it("Should emit RollResult event", async function () {
            await expect(craps.connect(owner).resolveRoll(7))
                .to.emit(craps, "RollResult")
                .withArgs(7);
        });

        it("Should clear resolved bets", async function () {
            await craps.connect(owner).resolveRoll(7);
            const bet = await craps.playerBets(addr1.address, 0);
            expect(bet.amount).to.equal(0);
            expect(bet.resolved).to.be.true;
            
            const activePlayers = await craps.getActivePlayers();
            expect(activePlayers).to.not.include(addr1.address);
        });
    });

    describe("Game State", function () {
        it("Should track point correctly", async function () {
            await craps.connect(owner).resolveRoll(4);
            expect(await craps.point()).to.equal(4);
            await craps.connect(owner).resolveRoll(7);
            expect(await craps.point()).to.equal(0);
        });

        it("Should manage game phases correctly", async function () {
            expect(await craps.currentPhase()).to.equal(0); // Off
            await craps.connect(owner).resolveRoll(4);
            expect(await craps.currentPhase()).to.equal(1); // Come
            await craps.connect(owner).resolveRoll(7);
            expect(await craps.currentPhase()).to.equal(0); // Off
        });
    });

    describe("Edge Cases", function () {
        it("Should handle invalid roll numbers", async function () {
            await expect(
                craps.connect(owner).resolveRoll(1)
            ).to.be.revertedWith("Invalid roll outcome.");
            await expect(
                craps.connect(owner).resolveRoll(13)
            ).to.be.revertedWith("Invalid roll outcome.");
        });

        it("Should handle multiple bet types", async function () {
            await craps.connect(addr1).placeBet(0, { value: minBetAmount }); // Pass
            await craps.connect(addr1).placeBet(4, { value: minBetAmount }); // Field
            const activePlayers = await craps.getActivePlayers();
            expect(activePlayers.length).to.equal(1);
        });
    });
});