const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Blackjack", function () {
  let Blackjack, blackjack, Treasury, treasury;
  let owner, player1, player2;
  const minBetAmount = ethers.parseEther("0.01");

  beforeEach(async function () {
    [owner, player1, player2] = await ethers.getSigners();

    // Deploy Treasury first
    Treasury = await ethers.getContractFactory("HouseTreasury");
    treasury = await Treasury.deploy();
    await treasury.waitForDeployment();

    // Deploy Blackjack with Treasury address
    Blackjack = await ethers.getContractFactory("Blackjack");
    blackjack = await Blackjack.deploy(minBetAmount, await treasury.getAddress());
    await blackjack.waitForDeployment();

    // Set Blackjack as authorized game in Treasury
    await treasury.connect(owner).authorizeGame(await blackjack.getAddress());

    // Fund Treasury
    await treasury.connect(owner).fundHouseTreasury({ value: ethers.parseEther("10") });

    // Create accounts and fund players
    await treasury.connect(player1).openAccount({ value: ethers.parseEther("0.1") });
    await treasury.connect(player2).openAccount({ value: ethers.parseEther("0.1") });
    await treasury.connect(player1).deposit({ value: ethers.parseEther("1") });
    await treasury.connect(player2).deposit({ value: ethers.parseEther("1") });

    // Reset cooldown for testing
    await blackjack.connect(owner).setActionCooldown(0);
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await blackjack.owner()).to.equal(owner.address);
    });

    it("Should set the correct minimum bet amount", async function () {
      expect(await blackjack.minBetAmount()).to.equal(minBetAmount);
    });

    it("Should set the correct treasury address", async function () {
      expect(await blackjack.treasury()).to.equal(await treasury.getAddress());
    });
  });

  describe("Betting", function () {
    beforeEach(async function () {
      // Ensure cooldown is reset
      await blackjack.connect(owner).setActionCooldown(0);
    });

    it("Should allow placing a valid bet", async function () {
      const betAmount = ethers.parseEther("0.1");
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
      ).to.be.revertedWith("Bet amount too low");
    });

    it("Should reject bet when player has insufficient treasury balance", async function () {
      const highBet = ethers.parseEther("2");
      await expect(
        blackjack.connect(player1).placeBet({ value: highBet })
      ).to.be.revertedWith("Insufficient balance or no active account");
    });

    it("Should reject multiple active bets from same player", async function () {
      const betAmount = ethers.parseEther("0.1");
      await blackjack.connect(player1).placeBet({ value: betAmount });
      await expect(
        blackjack.connect(player1).placeBet({ value: betAmount })
      ).to.be.revertedWithCustomError(blackjack, "PlayerAlreadyHasActiveBet");
    });
  });

  describe("Game Resolution", function () {
    const betAmount = ethers.parseEther("0.1");

    beforeEach(async function () {
      await blackjack.connect(player1).placeBet({ value: betAmount });
    });

    it("Should allow owner to resolve games", async function () {
      const expectedWinnings = betAmount * BigInt(2); // Use BigInt multiplication
      await expect(
        blackjack.connect(owner).resolveGames(
          [player1.address],
          [2] // 2x multiplier for win
        )
      ).to.emit(blackjack, "GameResolved")
        .withArgs(player1.address, expectedWinnings);
    });

    it("Should prevent non-owner from resolving games", async function () {
      await expect(
        blackjack.connect(player2).resolveGames([player1.address], [2])
      ).to.be.revertedWithCustomError(blackjack, "OnlyOwnerAllowed");
    });

    it("Should clear player's active game after resolution", async function () {
      await blackjack.connect(owner).resolveGames([player1.address], [2]);
      const playerHand = await blackjack.playerHands(player1.address);
      expect(playerHand.bet).to.equal(0);
      expect(playerHand.resolved).to.equal(false);
    });
  });

  describe("Circuit Breakers", function () {
    it("Should enforce rate limiting between bets", async function () {
      const betAmount = ethers.parseEther("0.1");
      
      // Set a non-zero cooldown
      await blackjack.connect(owner).setActionCooldown(60); // 60 seconds
      
      await blackjack.connect(player1).placeBet({ value: betAmount });
      await blackjack.connect(owner).resolveGames([player1.address], [0]);
      
      await expect(
        blackjack.connect(player1).placeBet({ value: betAmount })
      ).to.be.revertedWithCustomError(blackjack, "ActionRateLimited");
    });

    it("Should allow owner to pause the contract", async function () {
      await blackjack.connect(owner).pause();
      const betAmount = ethers.parseEther("0.1");
      await expect(
        blackjack.connect(player1).placeBet({ value: betAmount })
      ).to.be.revertedWith("Contract is paused");
    });

    it("Should allow owner to unpause the contract", async function () {
      await blackjack.connect(owner).pause();
      await blackjack.connect(owner).unpause();
      await blackjack.connect(owner).setActionCooldown(0);
      const betAmount = ethers.parseEther("0.1");
      await expect(blackjack.connect(player1).placeBet({ value: betAmount }))
        .to.emit(blackjack, "BetPlaced");
    });
  });

  describe("Active Players", function () {
    beforeEach(async function () {
      await blackjack.connect(owner).setActionCooldown(0);
    });

    it("Should track active players correctly", async function () {
      const betAmount = ethers.parseEther("0.1");
      
      // Place bets
      await blackjack.connect(player1).placeBet({ value: betAmount });
      await blackjack.connect(player2).placeBet({ value: betAmount });

      // Check active players
      const activePlayers = await blackjack.getActivePlayers();
      expect(activePlayers).to.have.lengthOf(2);
      expect(activePlayers).to.include(player1.address);
      expect(activePlayers).to.include(player2.address);

      // Resolve games
      await blackjack.connect(owner).resolveGames(
        [player1.address, player2.address],
        [0, 0]
      );

      // Check active players cleared
      const activePlayersAfter = await blackjack.getActivePlayers();
      expect(activePlayersAfter).to.have.lengthOf(0);
    });
  });
});