const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Balatro", function () {
    let Balatro, balatro, Treasury, treasury;
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

        // Deploy Balatro
        Balatro = await ethers.getContractFactory("Balatro");
        balatro = await Balatro.deploy(minBetAmount, await treasury.getAddress());
        await balatro.waitForDeployment();

        // Setup Treasury
        await treasury.connect(owner).authorizeGame(await balatro.getAddress());
        await treasury.connect(owner).fundHouseTreasury({ value: initialFunds });

        // Setup player accounts
        await treasury.connect(player1).openAccount({ value: playerFunds });
        await treasury.connect(player2).openAccount({ value: playerFunds });
    });

    describe("Deployment", function () {
        it("Should set the correct initial values", async function () {
            expect(await balatro.owner()).to.equal(owner.address);
            expect(await balatro.minBetAmount()).to.equal(minBetAmount);
            expect(await balatro.treasury()).to.equal(await treasury.getAddress());
        });

        it("Should initialize with no active games", async function () {
            expect(await balatro.isPlayerActive(player1.address)).to.be.false;
            const activePlayers = await balatro.getActivePlayers();
            expect(activePlayers.length).to.equal(0);
        });
    });

    describe("Game Start", function () {
        it("Should allow starting a game with valid bet", async function () {
            await expect(balatro.connect(player1).startGame({ value: betAmount }))
                .to.emit(balatro, "GameStarted")
                .withArgs(player1.address, betAmount);

            const game = await balatro.connect(player1).getActiveGame();
            expect(game.state).to.equal(1); // GameState.InProgress
            expect(game.roundNumber).to.equal(1);
            expect(game.score).to.equal(0);
        });

        it("Should reject bet below minimum", async function () {
            const lowBet = ethers.parseEther("0.001");
            await expect(
                balatro.connect(player1).startGame({ value: lowBet })
            ).to.be.revertedWithCustomError(balatro, "InsufficientBet");
        });

        it("Should reject starting multiple games", async function () {
            await balatro.connect(player1).startGame({ value: betAmount });
            await expect(
                balatro.connect(player1).startGame({ value: betAmount })
            ).to.be.revertedWithCustomError(balatro, "GameAlreadyInProgress");
        });

        it("Should add player to active players list", async function () {
            await balatro.connect(player1).startGame({ value: betAmount });
            expect(await balatro.isPlayerActive(player1.address)).to.be.true;
            const activePlayers = await balatro.getActivePlayers();
            expect(activePlayers).to.include(player1.address);
        });
    });

    describe("Card Drawing", function () {
        beforeEach(async function () {
            await balatro.connect(player1).startGame({ value: betAmount });
        });

        it("Should allow drawing cards", async function () {
            await expect(balatro.connect(player1).drawCard())
                .to.emit(balatro, "CardDrawn");

            const game = await balatro.connect(player1).getActiveGame();
            expect(game.hands.length).to.be.greaterThan(0);
            expect(game.hands[0].cards.length).to.equal(1);
        });

        it("Should only allow active players to draw cards", async function () {
            await expect(
                balatro.connect(player2).drawCard()
            ).to.be.revertedWithCustomError(balatro, "NoActiveGame");
        });

        it("Should generate valid card values", async function () {
            await balatro.connect(player1).drawCard();
            const game = await balatro.connect(player1).getActiveGame();
            const card = game.hands[0].cards[0];
            
            // Check if card rank is valid (1-13 or 0 for Joker)
            expect(card.rank).to.be.within(0, 13);
            
            // Check if suit is valid (0-4, including Joker)
            expect(Number(card.suit)).to.be.within(0, 4);
        });
    });

    describe("Hand Completion", function () {
        beforeEach(async function () {
            await balatro.connect(player1).startGame({ value: betAmount });
            // Draw 5 cards
            for (let i = 0; i < 5; i++) {
                await balatro.connect(player1).drawCard();
            }
        });

        it("Should allow completing a hand with enough cards", async function () {
            await expect(balatro.connect(player1).completeHand())
                .to.emit(balatro, "HandCompleted");
        });

        it("Should reject completing hand with insufficient cards", async function () {
            await balatro.connect(player2).startGame({ value: betAmount });
            // Draw only 4 cards
            for (let i = 0; i < 4; i++) {
                await balatro.connect(player2).drawCard();
            }
            
            await expect(
                balatro.connect(player2).completeHand()
            ).to.be.revertedWith("Not enough cards in hand");
        });

        it("Should calculate correct multipliers for poker hands", async function () {
            await balatro.connect(player1).completeHand();
            const game = await balatro.connect(player1).getActiveGame();
            expect(game.totalMultiplier).to.be.at.least(1);
        });

        it("Should start new round after hand completion", async function () {
            await balatro.connect(player1).completeHand();
            const game = await balatro.connect(player1).getActiveGame();
            expect(game.roundNumber).to.equal(2);
            expect(game.hands.length).to.equal(2);
        });
    });

    describe("Game Completion", function () {
        beforeEach(async function () {
            await balatro.connect(player1).startGame({ value: betAmount });
        });

        it("Should complete game after three rounds", async function () {
            // Complete three rounds
            for (let round = 0; round < 3; round++) {
                // Draw 5 cards
                for (let i = 0; i < 5; i++) {
                    await balatro.connect(player1).drawCard();
                }
                await balatro.connect(player1).completeHand();
            }

            // Check game is completed
            const game = await balatro.connect(player1).getActiveGame();
            expect(game.state).to.equal(2); // GameState.Completed
            expect(await balatro.isPlayerActive(player1.address)).to.be.false;
        });

        it("Should process winnings correctly", async function () {
            const initialBalance = await treasury.getPlayerBalance(player1.address);
            
            // Complete three rounds
            for (let round = 0; round < 3; round++) {
                for (let i = 0; i < 5; i++) {
                    await balatro.connect(player1).drawCard();
                }
                await balatro.connect(player1).completeHand();
            }

            const finalBalance = await treasury.getPlayerBalance(player1.address);
            expect(finalBalance).to.not.equal(initialBalance); // Balance should change
        });

        it("Should remove player from active list after completion", async function () {
            // Complete three rounds
            for (let round = 0; round < 3; round++) {
                for (let i = 0; i < 5; i++) {
                    await balatro.connect(player1).drawCard();
                }
                await balatro.connect(player1).completeHand();
            }

            const activePlayers = await balatro.getActivePlayers();
            expect(activePlayers).to.not.include(player1.address);
        });
    });

    describe("Treasury Integration", function () {
        it("Should update house funds on game start", async function () {
            const initialHouseFunds = await treasury.getHouseFunds();
            await balatro.connect(player1).startGame({ value: betAmount });
            const finalHouseFunds = await treasury.getHouseFunds();
            expect(finalHouseFunds).to.equal(initialHouseFunds + betAmount);
        });

        it("Should update house funds on game completion", async function () {
            await balatro.connect(player1).startGame({ value: betAmount });
            const initialHouseFunds = await treasury.getHouseFunds();

            // Complete three rounds
            for (let round = 0; round < 3; round++) {
                for (let i = 0; i < 5; i++) {
                    await balatro.connect(player1).drawCard();
                }
                await balatro.connect(player1).completeHand();
            }

            const finalHouseFunds = await treasury.getHouseFunds();
            expect(finalHouseFunds).to.not.equal(initialHouseFunds); // Funds should change
        });
    });
}); 