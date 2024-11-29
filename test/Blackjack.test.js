const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Blackjack", function () {
  let Blackjack, blackjack, Treasury, treasury;
  let owner, player1, player2;
  const minBetAmount = ethers.parseEther("0.01");
  const initialFunds = ethers.parseEther("10");
  const playerFunds = ethers.parseEther("1");
  const betAmount = ethers.parseEther("0.1");

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

    it("Should initialize with empty player hands", async function () {
      const hand = await blackjack.getPlayerHand(player1.address);
      expect(hand.bet).to.equal(0);
      expect(hand.resolved).to.be.false;
      expect(hand.cards.length).to.equal(0);
    });
  });

  describe("Betting", function () {
    it("Should allow placing a valid bet", async function () {
      await expect(blackjack.connect(player1).placeBet(betAmount))
        .to.emit(blackjack, "BetPlaced")
        .withArgs(player1.address, betAmount);

      const playerHand = await blackjack.playerHands(player1.address);
      expect(playerHand.bet).to.equal(betAmount);
      expect(playerHand.resolved).to.be.false;
    });

    it("Should deduct bet amount from player's treasury balance", async function () {
      const initialBalance = await treasury.getPlayerBalance(player1.address);
      await blackjack.connect(player1).placeBet(betAmount);
      const finalBalance = await treasury.getPlayerBalance(player1.address);
      expect(finalBalance).to.equal(initialBalance - betAmount);
    });

    it("Should reject bet below minimum", async function () {
      const lowBet = ethers.parseEther("0.001");
      await expect(
        blackjack.connect(player1).placeBet(lowBet)
      ).to.be.revertedWithCustomError(blackjack, "BetBelowMinimum");
    });

    it("Should reject bet with insufficient treasury balance", async function () {
      const highBet = ethers.parseEther("2");
      await expect(
        blackjack.connect(player1).placeBet(highBet)
      ).to.be.revertedWithCustomError(blackjack, "InsufficientTreasuryBalance");
    });

    it("Should reject multiple active bets", async function () {
      await blackjack.connect(player1).placeBet(betAmount);
      await expect(
        blackjack.connect(player1).placeBet(betAmount)
      ).to.be.revertedWithCustomError(blackjack, "PlayerAlreadyHasActiveBet");
    });
  });

  describe("Player Management", function () {
    beforeEach(async function () {
      await blackjack.connect(player1).placeBet(betAmount);
    });

    it("Should track active players correctly", async function () {
      expect(await blackjack.isPlayerActive(player1.address)).to.be.true;
      const activePlayers = await blackjack.getActivePlayers();
      expect(activePlayers).to.include(player1.address);
    });

    it("Should remove player from active list after game resolution", async function () {
      await blackjack.connect(owner).resolveGames([player1.address], [0]);
      expect(await blackjack.isPlayerActive(player1.address)).to.be.false;
      const activePlayers = await blackjack.getActivePlayers();
      expect(activePlayers).to.not.include(player1.address);
    });

    it("Should enforce rate limiting between bets", async function () {
      await blackjack.connect(owner).setActionCooldown(60);
      await blackjack.connect(owner).resolveGames([player1.address], [0]);
      
      await expect(
        blackjack.connect(player1).placeBet(betAmount)
      ).to.be.revertedWithCustomError(blackjack, "ActionRateLimited");
    });
  });

  describe("Game Resolution", function () {
    beforeEach(async function () {
      await blackjack.connect(player1).placeBet(betAmount);
      await blackjack.connect(player2).placeBet(betAmount);
    });

    it("Should resolve winning games with correct payout", async function () {
      const initialBalance = await treasury.getPlayerBalance(player1.address);
      await blackjack.connect(owner).resolveGames([player1.address], [2]);
      const finalBalance = await treasury.getPlayerBalance(player1.address);
      expect(finalBalance).to.equal(initialBalance + betAmount * BigInt(2));
    });

    it("Should resolve losing games correctly", async function () {
      const initialBalance = await treasury.getPlayerBalance(player1.address);
      await blackjack.connect(owner).resolveGames([player1.address], [0]);
      const finalBalance = await treasury.getPlayerBalance(player1.address);
      expect(finalBalance).to.equal(initialBalance);
    });

    it("Should resolve push games correctly", async function () {
      const initialBalance = await treasury.getPlayerBalance(player1.address);
      await blackjack.connect(owner).resolveGames([player1.address], [1]);
      const finalBalance = await treasury.getPlayerBalance(player1.address);
      expect(finalBalance).to.equal(initialBalance + betAmount);
    });

    it("Should resolve multiple games simultaneously", async function () {
      await blackjack.connect(owner).resolveGames(
        [player1.address, player2.address],
        [2, 0]
      );

      const player1Balance = await treasury.getPlayerBalance(player1.address);
      const player2Balance = await treasury.getPlayerBalance(player2.address);

      expect(player1Balance).to.be.gt(playerFunds);
      expect(player2Balance).to.be.lt(playerFunds);
    });

    it("Should emit correct events on game resolution", async function () {
      await expect(blackjack.connect(owner).resolveGames([player1.address], [2]))
        .to.emit(blackjack, "GameResolved")
        .withArgs(player1.address, betAmount * BigInt(2));
    });

    it("Should clear player state after resolution", async function () {
      await blackjack.connect(owner).resolveGames([player1.address], [2]);
      const hand = await blackjack.getPlayerHand(player1.address);
      expect(hand.bet).to.equal(0);
      expect(hand.resolved).to.be.false;
      expect(hand.cards.length).to.equal(0);
    });
  });

  describe("Security Features", function () {
    it("Should prevent non-owner from resolving games", async function () {
      await blackjack.connect(player1).placeBet(betAmount);
      await expect(
        blackjack.connect(player2).resolveGames([player1.address], [2])
      ).to.be.revertedWithCustomError(blackjack, "OnlyOwnerAllowed");
    });

    it("Should prevent resolution during paused state", async function () {
      await blackjack.connect(player1).placeBet(betAmount);
      await blackjack.connect(owner).pause();
      
      await expect(
        blackjack.connect(owner).resolveGames([player1.address], [2])
      ).to.be.revertedWithCustomError(blackjack, "GamePaused");
    });

    it("Should prevent betting during paused state", async function () {
      await blackjack.connect(owner).pause();
      await expect(
        blackjack.connect(player1).placeBet(betAmount)
      ).to.be.revertedWithCustomError(blackjack, "GamePaused");
    });

    it("Should only allow owner to modify action cooldown", async function () {
      await expect(
        blackjack.connect(player1).setActionCooldown(30)
      ).to.be.revertedWithCustomError(blackjack, "OnlyOwnerAllowed");
    });
  });

  describe("Treasury Integration", function () {
    it("Should update house funds on player loss", async function () {
      const initialHouseFunds = await treasury.getHouseFunds();
      await blackjack.connect(player1).placeBet(betAmount);
      await blackjack.connect(owner).resolveGames([player1.address], [0]);
      const finalHouseFunds = await treasury.getHouseFunds();
      expect(finalHouseFunds).to.equal(initialHouseFunds + betAmount);
    });

    it("Should update house funds on player win", async function () {
      const initialHouseFunds = await treasury.getHouseFunds();
      await blackjack.connect(player1).placeBet(betAmount);
      await blackjack.connect(owner).resolveGames([player1.address], [2]);
      const finalHouseFunds = await treasury.getHouseFunds();
      expect(finalHouseFunds).to.equal(initialHouseFunds - betAmount);
    });
  });
});