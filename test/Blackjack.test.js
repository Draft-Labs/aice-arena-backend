const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Blackjack", function () {
  let Blackjack, blackjack, Treasury, treasury;
  let owner, player1, player2;
  const minBetAmount = ethers.parseEther("0.01");
  const initialFunds = ethers.parseEther("10");
  const playerFunds = ethers.parseEther("1");

  beforeEach(async function () {
    [owner, player1, player2] = await ethers.getSigners();

    // Deploy Treasury
    Treasury = await ethers.getContractFactory("HouseTreasury");
    treasury = await Treasury.deploy();
    await treasury.waitForDeployment();

    // Deploy Blackjack
    Blackjack = await ethers.getContractFactory("Blackjack");
    blackjack = await Blackjack.deploy(minBetAmount, await treasury.getAddress());
    await blackjack.waitForDeployment();

    // Setup Treasury
    await treasury.connect(owner).authorizeGame(await blackjack.getAddress());
    await treasury.connect(owner).fundHouseTreasury({ value: initialFunds });

    // Setup player accounts
    await treasury.connect(player1).openAccount({ value: playerFunds });
    await treasury.connect(player2).openAccount({ value: playerFunds });

    // Reset cooldown for testing
    await blackjack.connect(owner).setActionCooldown(0);
  });

  describe("Deployment", function () {
    it("Should set the correct initial values", async function () {
      expect(await blackjack.owner()).to.equal(owner.address);
      expect(await blackjack.minBetAmount()).to.equal(minBetAmount);
      expect(await blackjack.treasury()).to.equal(await treasury.getAddress());
    });
  });

  describe("Betting", function () {
    const betAmount = ethers.parseEther("0.1");

    it("Should allow placing a valid bet", async function () {
      await expect(blackjack.connect(player1).placeBet({ value: betAmount }))
        .to.emit(blackjack, "BetPlaced")
        .withArgs(player1.address, betAmount);

      const playerHand = await blackjack.playerHands(player1.address);
      expect(playerHand.bet).to.equal(betAmount);
      expect(playerHand.resolved).to.equal(false);
    });

    it("Should reject bet below minimum", async function () {
      const lowBet = ethers.parseEther("0.001");
      await expect(
        blackjack.connect(player1).placeBet({ value: lowBet })
      ).to.be.revertedWithCustomError(blackjack, "BetBelowMinimum");
    });

    it("Should reject bet with insufficient treasury balance", async function () {
      const highBet = ethers.parseEther("2");
      await expect(
        blackjack.connect(player1).placeBet({ value: highBet })
      ).to.be.revertedWithCustomError(blackjack, "InsufficientTreasuryBalance");
    });

    it("Should reject multiple active bets", async function () {
      await blackjack.connect(player1).placeBet({ value: betAmount });
      await expect(
        blackjack.connect(player1).placeBet({ value: betAmount })
      ).to.be.revertedWithCustomError(blackjack, "PlayerAlreadyHasActiveBet");
    });

    it("Should track active players correctly", async function () {
      await blackjack.connect(player1).placeBet({ value: betAmount });
      expect(await blackjack.isPlayerActive(player1.address)).to.be.true;
      
      const activePlayers = await blackjack.getActivePlayers();
      expect(activePlayers).to.include(player1.address);
    });
  });

  describe("Game Resolution", function () {
    const betAmount = ethers.parseEther("0.1");

    beforeEach(async function () {
      await blackjack.connect(player1).placeBet({ value: betAmount });
    });

    it("Should allow owner to resolve winning games", async function () {
      const multiplier = 2;
      const expectedWinnings = betAmount * BigInt(multiplier);

      await expect(
        blackjack.connect(owner).resolveGames([player1.address], [multiplier])
      ).to.emit(blackjack, "GameResolved")
        .withArgs(player1.address, expectedWinnings);

      const isActive = await blackjack.isPlayerActive(player1.address);
      expect(isActive).to.be.false;
    });

    it("Should allow owner to resolve losing games", async function () {
      await expect(
        blackjack.connect(owner).resolveGames([player1.address], [0])
      ).to.not.be.reverted;

      const playerHand = await blackjack.playerHands(player1.address);
      expect(playerHand.bet).to.equal(0);
      expect(playerHand.resolved).to.be.false;
    });

    it("Should prevent non-owner from resolving games", async function () {
      await expect(
        blackjack.connect(player2).resolveGames([player1.address], [2])
      ).to.be.revertedWithCustomError(blackjack, "OnlyOwnerAllowed");
    });

    it("Should handle multiple game resolutions", async function () {
      await blackjack.connect(player2).placeBet({ value: betAmount });
      
      await blackjack.connect(owner).resolveGames(
        [player1.address, player2.address],
        [2, 0]
      );

      expect(await blackjack.isPlayerActive(player1.address)).to.be.false;
      expect(await blackjack.isPlayerActive(player2.address)).to.be.false;
    });
  });

  describe("Circuit Breakers", function () {
    const betAmount = ethers.parseEther("0.1");

    it("Should allow owner to pause the contract", async function () {
      await blackjack.connect(owner).pause();
      await expect(
        blackjack.connect(player1).placeBet({ value: betAmount })
      ).to.be.revertedWithCustomError(blackjack, "GamePaused");
    });

    it("Should enforce rate limiting", async function () {
      await blackjack.connect(owner).setActionCooldown(60);
      
      // Place bet and resolve it first
      await blackjack.connect(player1).placeBet({ value: betAmount });
      await blackjack.connect(owner).resolveGames([player1.address], [0]);
      
      // Try to place another bet immediately
      await expect(
        blackjack.connect(player1).placeBet({ value: betAmount })
      ).to.be.revertedWithCustomError(blackjack, "ActionRateLimited");
    });

    it("Should allow owner to unpause the contract", async function () {
      await blackjack.connect(owner).pause();
      await blackjack.connect(owner).unpause();
      await expect(
        blackjack.connect(player1).placeBet({ value: betAmount })
      ).not.to.be.reverted;
    });

    it("Should prevent non-owner from pausing", async function () {
      await expect(
        blackjack.connect(player1).pause()
      ).to.be.revertedWithCustomError(blackjack, "OnlyOwnerAllowed");
    });
  });

  describe("Administrative Functions", function () {
    it("Should allow owner to set action cooldown", async function () {
      const newCooldown = 120;
      await blackjack.connect(owner).setActionCooldown(newCooldown);
      
      // Place bet and resolve it first
      const betAmount = ethers.parseEther("0.1");
      await blackjack.connect(player1).placeBet({ value: betAmount });
      await blackjack.connect(owner).resolveGames([player1.address], [0]);
      
      // Try to place another bet immediately
      await expect(
        blackjack.connect(player1).placeBet({ value: betAmount })
      ).to.be.revertedWithCustomError(blackjack, "ActionRateLimited");
    });

    it("Should prevent non-owner from setting cooldown", async function () {
      await expect(
        blackjack.connect(player1).setActionCooldown(120)
      ).to.be.revertedWithCustomError(blackjack, "OnlyOwnerAllowed");
    });
  });
});