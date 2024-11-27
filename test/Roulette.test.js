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
        
        // Deploy Treasury
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await (await HouseTreasury.deploy()).waitForDeployment();
        
        // Deploy Roulette
        Roulette = await ethers.getContractFactory("Roulette");
        roulette = await (await Roulette.deploy(minBetAmount, treasury.getAddress())).waitForDeployment();
        
        // Setup
        await treasury.connect(owner).authorizeGame(await roulette.getAddress());
        await treasury.connect(owner).fundTreasury({ 
            value: ethers.parseEther("100.0") 
        });
    });

    describe("Deployment", function () {
        it("Should set the correct owner", async function () {
            expect(await roulette.owner()).to.equal(owner.address);
        });

        it("Should set the correct minimum bet", async function () {
            expect(await roulette.minBetAmount()).to.equal(minBetAmount);
        });

        it("Should set the correct treasury address", async function () {
            expect(await roulette.treasury()).to.equal(await treasury.getAddress());
        });
    });

    describe("Betting Functions", function () {
        describe("Straight Bets", function () {
            it("Should allow placing a straight bet", async function () {
                await roulette.connect(addr1).placeBet(0, [17], { value: minBetAmount });
                const bets = await roulette.getPlayerBets(addr1.address);
                expect(bets.length).to.equal(1);
                expect(bets[0].betType).to.equal(0); // Straight
                expect(bets[0].amount).to.equal(minBetAmount);
                expect(bets[0].numbers[0]).to.equal(17);
            });

            it("Should reject invalid straight bet numbers", async function () {
                await expect(
                    roulette.connect(addr1).placeBet(0, [37], { value: minBetAmount })
                ).to.be.revertedWith("Invalid bet configuration.");
            });
        });

        describe("Split Bets", function () {
            it("Should allow placing a split bet", async function () {
                await roulette.connect(addr1).placeBet(1, [17, 18], { value: minBetAmount });
                const bets = await roulette.getPlayerBets(addr1.address);
                expect(bets[0].betType).to.equal(1); // Split
                expect(bets[0].numbers.length).to.equal(2);
            });
        });

        describe("Even Money Bets", function () {
            it("Should allow placing red/black bets", async function () {
                await roulette.connect(addr1).placeBet(7, [], { value: minBetAmount }); // Red
                await roulette.connect(addr1).placeBet(8, [], { value: minBetAmount }); // Black
                const bets = await roulette.getPlayerBets(addr1.address);
                expect(bets.length).to.equal(2);
            });

            it("Should allow placing even/odd bets", async function () {
                await roulette.connect(addr1).placeBet(9, [], { value: minBetAmount }); // Even
                await roulette.connect(addr1).placeBet(10, [], { value: minBetAmount }); // Odd
                const bets = await roulette.getPlayerBets(addr1.address);
                expect(bets.length).to.equal(2);
            });
        });

        it("Should reject bet below minimum", async function () {
            await expect(
                roulette.connect(addr1).placeBet(0, [17], { 
                    value: ethers.parseEther("0.005") 
                })
            ).to.be.revertedWith("Bet amount is below minimum required.");
        });
    });

    describe("Spin Resolution", function () {
        beforeEach(async function () {
            await roulette.connect(addr1).placeBet(0, [17], { value: minBetAmount }); // Straight bet on 17
        });

        it("Should resolve winning straight bet correctly", async function () {
            const initialBalance = await ethers.provider.getBalance(addr1.address);
            await roulette.connect(owner).spin(17);
            const finalBalance = await ethers.provider.getBalance(addr1.address);
            
            // Straight bet pays 35:1 plus original bet (36x total)
            expect(finalBalance).to.be.closeTo(
                initialBalance + (minBetAmount * BigInt(36)),
                ethers.parseEther("0.001") // Allow for gas costs
            );
        });

        it("Should clear bets after spin", async function () {
            await roulette.connect(owner).spin(17);
            const bets = await roulette.getPlayerBets(addr1.address);
            expect(bets.length).to.equal(0);
        });

        it("Should handle losing bets correctly", async function () {
            const initialBalance = await ethers.provider.getBalance(addr1.address);
            await roulette.connect(owner).spin(18);
            const finalBalance = await ethers.provider.getBalance(addr1.address);
            expect(finalBalance).to.be.closeTo(initialBalance, ethers.parseEther("0.001"));
        });
    });

    describe("Access Control", function () {
        it("Should only allow owner to spin", async function () {
            await expect(
                roulette.connect(addr1).spin(17)
            ).to.be.revertedWith("Only owner can call this function.");
        });
    });

    describe("Edge Cases", function () {
        it("Should handle invalid spin numbers", async function () {
            await expect(
                roulette.connect(owner).spin(37)
            ).to.be.revertedWith("Invalid roulette number.");
        });

        it("Should handle multiple bets from same player", async function () {
            await roulette.connect(addr1).placeBet(0, [17], { value: minBetAmount }); // Straight
            await roulette.connect(addr1).placeBet(7, [], { value: minBetAmount }); // Red
            
            const bets = await roulette.getPlayerBets(addr1.address);
            expect(bets.length).to.equal(2);
        });

        it("Should handle zero (house number)", async function () {
            await roulette.connect(addr1).placeBet(7, [], { value: minBetAmount }); // Red
            await roulette.connect(owner).spin(0);
            const bets = await roulette.getPlayerBets(addr1.address);
            expect(bets.length).to.equal(0); // Ensure bets are cleared
        });
    });

    describe("Event Emission", function () {
        it("Should emit BetPlaced event", async function () {
            await expect(roulette.connect(addr1).placeBet(0, [17], { value: minBetAmount }))
                .to.emit(roulette, "BetPlaced")
                .withArgs(addr1.address, 0, minBetAmount, [17]);
        });

        it("Should emit SpinResult event", async function () {
            await expect(roulette.connect(owner).spin(17))
                .to.emit(roulette, "SpinResult")
                .withArgs(17);
        });
    });
});