const { expect } = require("chai");
const { ethers } = require("hardhat");

// Start the test suite
describe("CrapsGame Contract", function () {
    let CrapsGame;
    let crapsGame;
    let owner;
    let addr1;
    let addr2;

    // Deploy the contract before each test
    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        CrapsGame = await ethers.getContractFactory("CrapsGame");
        crapsGame = await CrapsGame.deploy();
        await crapsGame.deployed();
    });

    // Test for contract funding
    it("Should allow the owner to fund the contract", async function () {
        await crapsGame.connect(owner).fundContract({ value: ethers.utils.parseEther("1.0") });
        const contractBalance = await ethers.provider.getBalance(crapsGame.address);
        expect(contractBalance).to.equal(ethers.utils.parseEther("1.0"));
    });

    // Test for placing a bet
    it("Should allow a player to place a bet", async function () {
        await crapsGame.connect(addr1).placeBet(0, { value: ethers.utils.parseEther("0.1") }); // BetType.Pass
        const bet = await crapsGame.bets(0);
        expect(bet.player).to.equal(addr1.address);
        expect(bet.amount).to.equal(ethers.utils.parseEther("0.1"));
    });

    // Test for resolving a roll
    it("Should resolve a roll and update player balances if they win", async function () {
        await crapsGame.connect(owner).fundContract({ value: ethers.utils.parseEther("1.0") });
        await crapsGame.connect(addr1).placeBet(0, { value: ethers.utils.parseEther("0.1") }); // BetType.Pass
        await crapsGame.connect(owner).resolveRoll(7); // Roll outcome of 7 means Pass wins
        const balance = await crapsGame.playerBalances(addr1.address);
        expect(balance).to.equal(ethers.utils.parseEther("0.2"));
    });

    // Test for withdrawing winnings
    it("Should allow a player to withdraw winnings", async function () {
        await crapsGame.connect(owner).fundContract({ value: ethers.utils.parseEther("1.0") });
        await crapsGame.connect(addr1).placeBet(0, { value: ethers.utils.parseEther("0.1") }); // BetType.Pass
        await crapsGame.connect(owner).resolveRoll(7); // Roll outcome of 7 means Pass wins

        const initialBalance = await ethers.provider.getBalance(addr1.address);
        const tx = await crapsGame.connect(addr1).withdrawWinnings();
        const receipt = await tx.wait();
        const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);

        const finalBalance = await ethers.provider.getBalance(addr1.address);
        const expectedBalance = initialBalance.add(ethers.utils.parseEther("0.2")).sub(gasUsed);

        expect(finalBalance).to.be.closeTo(expectedBalance, ethers.utils.parseEther("0.001"));
    });
});