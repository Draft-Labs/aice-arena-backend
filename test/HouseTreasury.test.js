const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("HouseTreasury", function () {
    let HouseTreasury;
    let treasury;
    let owner;
    let addr1;
    let addr2;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        
        // Deploy Treasury
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await (await HouseTreasury.deploy()).waitForDeployment();
    });

    describe("Deployment", function () {
        it("Should set the correct owner", async function () {
            expect(await treasury.owner()).to.equal(owner.address);
        });
    });

    describe("Authorization", function () {
        it("Should authorize a game", async function () {
            await treasury.connect(owner).authorizeGame(addr1.address);
            expect(await treasury.authorizedGames(addr1.address)).to.be.true;
        });

        it("Should deauthorize a game", async function () {
            await treasury.connect(owner).authorizeGame(addr1.address);
            await treasury.connect(owner).deauthorizeGame(addr1.address);
            expect(await treasury.authorizedGames(addr1.address)).to.be.false;
        });

        it("Should only allow owner to authorize games", async function () {
            await expect(
                treasury.connect(addr1).authorizeGame(addr2.address)
            ).to.be.revertedWith("Only owner can call this function.");
        });

        it("Should only allow owner to deauthorize games", async function () {
            await expect(
                treasury.connect(addr1).deauthorizeGame(addr2.address)
            ).to.be.revertedWith("Only owner can call this function.");
        });
    });

    describe("Funding", function () {
        it("Should allow owner to fund the treasury", async function () {
            await treasury.connect(owner).fundTreasury({ value: ethers.parseEther("1.0") });
            expect(await treasury.getTreasuryBalance()).to.equal(ethers.parseEther("1.0"));
        });

        it("Should reject funding with zero value", async function () {
            await expect(
                treasury.connect(owner).fundTreasury({ value: ethers.parseEther("0.0") })
            ).to.be.revertedWith("Must send some Ether to fund the treasury.");
        });

        it("Should only allow owner to fund the treasury", async function () {
            await expect(
                treasury.connect(addr1).fundTreasury({ value: ethers.parseEther("1.0") })
            ).to.be.revertedWith("Only owner can call this function.");
        });
    });

    describe("Payouts", function () {
        beforeEach(async function () {
            await treasury.connect(owner).authorizeGame(addr1.address);
            await treasury.connect(owner).fundTreasury({ value: ethers.parseEther("10.0") });
        });

        it("Should allow authorized game to payout", async function () {
            const initialBalance = await ethers.provider.getBalance(addr2.address);
            await treasury.connect(addr1).payout(addr2.address, ethers.parseEther("1.0"));
            const finalBalance = await ethers.provider.getBalance(addr2.address);
            expect(finalBalance).to.equal(initialBalance + ethers.parseEther("1.0"));
        });

        it("Should reject payout if not enough balance", async function () {
            await expect(
                treasury.connect(addr1).payout(addr2.address, ethers.parseEther("20.0"))
            ).to.be.revertedWith("Not enough balance in treasury to payout.");
        });

        it("Should reject payout from unauthorized game", async function () {
            await expect(
                treasury.connect(addr2).payout(addr1.address, ethers.parseEther("1.0"))
            ).to.be.revertedWith("Only authorized games can call this function.");
        });
    });
});