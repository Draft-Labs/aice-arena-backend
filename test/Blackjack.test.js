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
    const minBetAmount = ethers.utils.parseEther("0.01");

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        
        // Deploy Treasury first
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await HouseTreasury.deploy();
        await treasury.deployed();

        // Deploy Blackjack with Treasury address
        Blackjack = await ethers.getContractFactory("Blackjack");
        blackjack = await Blackjack.deploy(minBetAmount, treasury.address);
        await blackjack.deployed();

        // Authorize Blackjack contract in Treasury
        await treasury.connect(owner).authorizeGame(blackjack.address);
        
        // Fund Treasury
        await treasury.connect(owner).fundTreasury({ value: ethers.utils.parseEther("10.0") });
    });

    describe("Treasury Setup", function () {
        it("Should set the correct owner", async function () {
            expect(await treasury.owner()).to.equal(owner.address);
        });

        it("Should authorize the Blackjack contract", async function () {
            expect(await treasury.authorizedGames(blackjack.address)).to.be.true;
        });

        it("Should allow owner to fund treasury", async function () {
            const balance = await treasury.getTreasuryBalance();
            expect(balance).to.equal(ethers.utils.parseEther("10.0"));
        });

        it("Should not allow non-owner to fund treasury", async function () {
            await expect(
                treasury.connect(addr1).fundTreasury({ value: ethers.utils.parseEther("1.0") })
            ).to.be.revertedWith("Only owner can call this function.");
        });
    });

    describe("Blackjack Setup", function () {
        it("Should set the correct minimum bet", async function () {
            expect(await blackjack.minBetAmount()).to.equal(minBetAmount);
        });

        it("Should set the correct treasury address", async function () {
            expect(await blackjack.treasury()).to.equal(treasury.address);
        });
    });

    describe("Betting Functions", function () {
        it("Should allow a valid bet", async function () {
            await blackjack.connect(addr1).placeBet({ value: minBetAmount });
            const bet = await blackjack.playerBets(addr1.address);
            expect(bet).to.equal(minBetAmount);
        });

        it("Should reject bet below minimum", async function () {
            await expect(
                blackjack.connect(addr1).placeBet({ 
                    value: ethers.utils.parseEther("0.005") 
                })
            ).to.be.revertedWith("Bet amount is below the minimum required.");
        });

        it("Should reject multiple active bets from same player", async function () {
            await blackjack.connect(addr1).placeBet({ value: minBetAmount });
            await expect(
                blackjack.connect(addr1).placeBet({ value: minBetAmount })
            ).to.be.revertedWith("Player already has an active bet.");
        });

        it("Should clear bet correctly", async function () {
            await blackjack.connect(addr1).placeBet({ value: minBetAmount });
            await blackjack.connect(owner).clearBet(addr1.address);
            const bet = await blackjack.playerBets(addr1.address);
            expect(bet).to.equal(0);
        });
    });

    describe("Payout Functions", function () {
        beforeEach(async function () {
            await blackjack.connect(addr1).placeBet({ value: minBetAmount });
        });

        it("Should payout winnings correctly", async function () {
            const initialBalance = await addr1.getBalance();
            const winAmount = ethers.utils.parseEther("0.02");

            await blackjack.connect(owner).payoutWinnings(addr1.address, winAmount);
            
            const finalBalance = await addr1.getBalance();
            expect(finalBalance.sub(initialBalance)).to.be.closeTo(
                winAmount,
                ethers.utils.parseEther("0.001") // Allow for gas costs
            );
        });

        it("Should clear bet after payout", async function () {
            await blackjack.connect(owner).payoutWinnings(
                addr1.address, 
                ethers.utils.parseEther("0.02")
            );
            const bet = await blackjack.playerBets(addr1.address);
            expect(bet).to.equal(0);
        });

        it("Should not allow payout without active bet", async function () {
            await expect(
                blackjack.connect(owner).payoutWinnings(
                    addr2.address, 
                    ethers.utils.parseEther("0.02")
                )
            ).to.be.revertedWith("Player does not have an active bet.");
        });

        it("Should not allow non-owner to payout", async function () {
            await expect(
                blackjack.connect(addr2).payoutWinnings(
                    addr1.address, 
                    ethers.utils.parseEther("0.02")
                )
            ).to.be.revertedWith("Only owner can call this function.");
        });
    });

    describe("Game State Management", function () {
        // Add tests for any game state management functions
        // Such as starting games, dealing cards, ending rounds, etc.
        // This section will depend on your specific game implementation
    });

    describe("Edge Cases", function () {
        it("Should handle zero address correctly", async function () {
            await expect(
                blackjack.connect(owner).payoutWinnings(
                    ethers.constants.AddressZero, 
                    ethers.utils.parseEther("0.02")
                )
            ).to.be.revertedWith("Player does not have an active bet.");
        });

        it("Should not allow payout greater than treasury balance", async function () {
            await blackjack.connect(addr1).placeBet({ value: minBetAmount });
            await expect(
                blackjack.connect(owner).payoutWinnings(
                    addr1.address, 
                    ethers.utils.parseEther("11.0") // More than treasury balance
                )
            ).to.be.revertedWith("Not enough balance in treasury to payout.");
        });
    });
});