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
        
        HouseTreasury = await ethers.getContractFactory("HouseTreasury");
        treasury = await (await HouseTreasury.deploy()).waitForDeployment();
    });

    describe("Account Management", function () {
        it("Should allow opening an account", async function () {
            await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
            expect(await treasury.activeAccounts(addr1.address)).to.be.true;
            expect(await treasury.playerBalances(addr1.address)).to.equal(ethers.parseEther("1.0"));
        });

        it("Should allow deposits to existing account", async function () {
            await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
            await treasury.connect(addr1).deposit({ value: ethers.parseEther("0.5") });
            expect(await treasury.playerBalances(addr1.address)).to.equal(ethers.parseEther("1.5"));
        });

        it("Should allow closing account and withdrawing funds", async function () {
            await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
            await treasury.connect(addr1).closeAccount();
            expect(await treasury.activeAccounts(addr1.address)).to.be.false;
            expect(await treasury.playerBalances(addr1.address)).to.equal(0);
        });

        it("Should reject deposits of 0 ETH", async function () {
            await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
            await expect(
                treasury.connect(addr1).deposit({ value: 0 })
            ).to.be.revertedWith("Must deposit some ETH");
        });

        it("Should reject deposits without active account", async function () {
            await expect(
                treasury.connect(addr1).deposit({ value: ethers.parseEther("1.0") })
            ).to.be.revertedWith("No active account");
        });

        it("Should allow partial withdrawals", async function () {
            await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
            await treasury.connect(addr1).withdraw(ethers.parseEther("0.4"));
            expect(await treasury.playerBalances(addr1.address)).to.equal(ethers.parseEther("0.6"));
        });

        it("Should reject withdrawals greater than balance", async function () {
            await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
            await expect(
                treasury.connect(addr1).withdraw(ethers.parseEther("1.1"))
            ).to.be.revertedWith("Insufficient balance");
        });

        it("Should reject withdrawals of 0 ETH", async function () {
            await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
            await expect(
                treasury.connect(addr1).withdraw(0)
            ).to.be.revertedWith("Must withdraw some ETH");
        });

        it("Should reject withdrawals without active account", async function () {
            await expect(
                treasury.connect(addr1).withdraw(ethers.parseEther("1.0"))
            ).to.be.revertedWith("No active account");
        });
    });

    describe("Game Authorization", function () {
        it("Should authorize a game", async function () {
            await treasury.connect(owner).authorizeGame(addr1.address);
            expect(await treasury.authorizedGames(addr1.address)).to.be.true;
        });

        it("Should deauthorize a game", async function () {
            await treasury.connect(owner).authorizeGame(addr1.address);
            await treasury.connect(owner).deauthorizeGame(addr1.address);
            expect(await treasury.authorizedGames(addr1.address)).to.be.false;
        });
    });

    describe("Bet Processing", function () {
        beforeEach(async function () {
            await treasury.connect(owner).authorizeGame(addr1.address);
            await treasury.connect(addr2).openAccount({ value: ethers.parseEther("1.0") });
        });

        it("Should allow authorized game to process bet loss", async function () {
            await treasury.connect(addr1).processBetLoss(addr2.address, ethers.parseEther("0.1"));
            expect(await treasury.playerBalances(addr2.address)).to.equal(ethers.parseEther("0.9"));
        });

        it("Should allow authorized game to process bet win", async function () {
            await treasury.connect(addr1).processBetWin(addr2.address, ethers.parseEther("0.2"));
            expect(await treasury.playerBalances(addr2.address)).to.equal(ethers.parseEther("1.2"));
        });

        it("Should verify if player can place bet", async function () {
            expect(await treasury.connect(addr1).canPlaceBet(addr2.address, ethers.parseEther("0.5"))).to.be.true;
            expect(await treasury.connect(addr1).canPlaceBet(addr2.address, ethers.parseEther("1.5"))).to.be.false;
        });
    });
});