const { expect } = require("chai");
const { ethers } = require("hardhat");

// Start the test suite
describe("Blackjack Contract", function () {
    let Blackjack;
    let blackjack;
    let owner;
    let addr1;
    let addr2;

    // Deploy the contract before each test
    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();  // Uses local Hardhat network accounts
        Blackjack = await ethers.getContractFactory("Blackjack");
        blackjack = await Blackjack.deploy(ethers.utils.parseEther("0.01"));
        await blackjack.deployed();  // Deploys contract on local Hardhat network
    });

    // Test for contract funding
    it("Should allow the owner to fund the contract", async function () {
        await blackjack.connect(owner).fundContract({ value: ethers.utils.parseEther("1.0") });
        const contractBalance = await ethers.provider.getBalance(blackjack.address);
        expect(contractBalance).to.equal(ethers.utils.parseEther("1.0"));
    });

    // Test placing a bet
    it("Should allow a user to place a bet", async function () {
        await blackjack.connect(addr1).placeBet({ value: ethers.utils.parseEther("0.01") });
        const bet = await blackjack.playerBets(addr1.address);
        expect(bet).to.equal(ethers.utils.parseEther("0.01"));
    });

    // Test failing to place a bet below the minimum
    it("Should fail if the bet amount is below the minimum", async function () {
        await expect(
            blackjack.connect(addr1).placeBet({ value: ethers.utils.parseEther("0.005") })
        ).to.be.revertedWith("Bet amount is below the minimum required.");
    });

    // Test payout winnings
    it("Should allow the owner to payout winnings", async function () {
        await blackjack.connect(owner).fundContract({ value: ethers.utils.parseEther("1.0") });
        await blackjack.connect(addr1).placeBet({ value: ethers.utils.parseEther("0.01") });

        await blackjack.connect(owner).payoutWinnings(addr1.address, ethers.utils.parseEther("0.02"));
        const newBalance = await ethers.provider.getBalance(blackjack.address);

        // Allow for a small margin due to gas costs
        expect(newBalance).to.be.closeTo(ethers.utils.parseEther("0.98"), ethers.utils.parseEther("0.01"));
    });
});
