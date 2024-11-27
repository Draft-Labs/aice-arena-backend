const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CrapsGame", function () {
    let HouseTreasury;
    let CrapsGame;
    let treasury;
    let craps;
    let owner;
    let addr1;
    let addr2;
    const minBetAmount = ethers.utils.parseEther("0.01");

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        
        // Deploy Treasury
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await HouseTreasury.deploy();
        await treasury.deployed();

        // Deploy CrapsGame
        CrapsGame = await ethers.getContractFactory("CrapsGame");
        craps = await CrapsGame.deploy(minBetAmount, treasury.address);
        await craps.deployed();

        // Setup
        await treasury.connect(owner).authorizeGame(craps.address);
        await treasury.connect(owner).fundTreasury({ 
            value: ethers.utils.parseEther("10.0") 
        });
    });

    describe("Deployment", function () {
        it("Should set the correct owner", async function () {
            expect(await craps.owner()).to.equal(owner.address);
        });

        it("Should set the correct minimum bet", async function () {
            expect(await craps.minBetAmount()).to.equal(minBetAmount);
        });

        it("Should set the correct treasury address", async function () {
            expect(await craps.treasury()).to.equal(treasury.address);
        });
    });

    describe("Betting Functions", function () {
        describe("Pass Line Bets", function () {
            it("Should allow placing a pass line bet", async function () {
                await craps.connect(addr1).placeBet(0, { value: minBetAmount });
                const bet = await craps.getPlayerBet(addr1.address, 0);
                expect(bet).to.equal(minBetAmount);
            });

            it("Should reject multiple pass line bets from same player", async function () {
                await craps.connect(addr1).placeBet(0, { value: minBetAmount });
                await expect(
                    craps.connect(addr1).placeBet(0, { value: minBetAmount })
                ).to.be.revertedWith("Player already has an active bet of this type.");
            });
        });

        describe("Don't Pass Bets", function () {
            it("Should allow placing a don't pass bet", async function () {
                await craps.connect(addr1).placeBet(1, { value: minBetAmount });
                const bet = await craps.getPlayerBet(addr1.address, 1);
                expect(bet).to.equal(minBetAmount);
            });
        });

        it("Should reject bet below minimum", async function () {
            await expect(
                craps.connect(addr1).placeBet(0, { 
                    value: ethers.utils.parseEther("0.005") 
                })
            ).to.be.revertedWith("Bet amount is below minimum required.");
        });
    });

    describe("Roll Resolution", function () {
        beforeEach(async function () {
            await craps.connect(addr1).placeBet(0, { value: minBetAmount }); // Pass Line bet
        });

        it("Should resolve winning Pass Line bet on 7 or 11", async function () {
            const initialBalance = await addr1.getBalance();
            const tx = await craps.connect(owner).resolveRoll(7);
            await tx.wait();
            
            const finalBalance = await addr1.getBalance();
            expect(finalBalance.sub(initialBalance)).to.be.closeTo(
                minBetAmount.mul(2),
                ethers.utils.parseEther("0.001") // Allow for gas costs
            );
        });

        it("Should clear bets after resolution", async function () {
            await craps.connect(owner).resolveRoll(7);
            const betsLength = await craps.getBetsLength();
            expect(betsLength).to.equal(0);
            const bet = await craps.getPlayerBet(addr1.address, 0);
            expect(bet).to.equal(0);
        });
    });

    describe("Access Control", function () {
        it("Should only allow owner to resolve rolls", async function () {
            await expect(
                craps.connect(addr1).resolveRoll(7)
            ).to.be.revertedWith("Only owner can call this function.");
        });
    });

    describe("Edge Cases", function () {
        it("Should handle invalid roll outcomes", async function () {
            await expect(
                craps.connect(owner).resolveRoll(1)
            ).to.be.revertedWith("Invalid roll outcome.");
            await expect(
                craps.connect(owner).resolveRoll(13)
            ).to.be.revertedWith("Invalid roll outcome.");
        });

        it("Should handle multiple bet types from same player", async function () {
            await craps.connect(addr1).placeBet(0, { value: minBetAmount }); // Pass
            await craps.connect(addr1).placeBet(2, { value: minBetAmount }); // Come
            
            const passLineBet = await craps.getPlayerBet(addr1.address, 0);
            const comeBet = await craps.getPlayerBet(addr1.address, 2);
            
            expect(passLineBet).to.equal(minBetAmount);
            expect(comeBet).to.equal(minBetAmount);
        });
    });
});