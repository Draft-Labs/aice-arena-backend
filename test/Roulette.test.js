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
        
        // Setup initial conditions
        await treasury.connect(owner).authorizeGame(await roulette.getAddress());
        await treasury.connect(owner).ownerFundTreasury({ value: ethers.parseEther("100.0") });
        await treasury.connect(addr1).openAccount({ value: ethers.parseEther("1.0") });
        await roulette.connect(owner).setActionCooldown(0);
    });

    describe("Deployment", function () {
        it("Should set the correct owner", async function () {
            expect(await roulette.owner()).to.equal(owner.address);
        });

        it("Should set the correct minimum bet amount", async function () {
            expect(await roulette.minBetAmount()).to.equal(minBetAmount);
        });

        it("Should set the correct treasury address", async function () {
            expect(await roulette.treasury()).to.equal(await treasury.getAddress());
        });
    });

    describe("Betting Functions", function () {
        it("Should allow placing multiple number bets", async function () {
            const numbers = [17, 18, 19];
            const totalBetAmount = minBetAmount * BigInt(numbers.length);
            
            await roulette.connect(addr1).placeBet(
                numbers,
                { value: totalBetAmount }
            );
            
            const bets = await roulette.getPlayerBets(addr1.address);
            expect(bets.length).to.equal(numbers.length);
            
            for (let i = 0; i < numbers.length; i++) {
                expect(bets[i].player).to.equal(addr1.address);
                expect(bets[i].amount).to.equal(minBetAmount);
                expect(bets[i].number).to.equal(numbers[i]);
            }
        });

        it("Should reject bets below minimum amount per number", async function () {
            const numbers = [17, 18];
            const invalidBetAmount = minBetAmount;  // Should be 2x minBetAmount for two numbers
            
            await expect(
                roulette.connect(addr1).placeBet(
                    numbers,
                    { value: invalidBetAmount }
                )
            ).to.be.revertedWith("Individual bet amount below minimum");
        });

        it("Should reject invalid roulette numbers", async function () {
            await expect(
                roulette.connect(addr1).placeBet(
                    [37],  // Invalid number (max is 36)
                    { value: minBetAmount }
                )
            ).to.be.revertedWith("Invalid roulette number");
        });

        it("Should track active players correctly", async function () {
            await roulette.connect(addr1).placeBet(
                [17],
                { value: minBetAmount }
            );
            const bets = await roulette.getPlayerBets(addr1.address);
            expect(bets.length).to.be.above(0);
        });
    });

    describe("Spin Resolution", function () {
        const betAmount = minBetAmount;
        let initialPlayerBalance;
        let initialHouseFunds;

        beforeEach(async function () {
            initialPlayerBalance = await treasury.getPlayerBalance(addr1.address);
            initialHouseFunds = await treasury.getHouseFunds();
            
            await roulette.connect(addr1).placeBet(
                [17],
                { value: betAmount }
            );
        });

        it("Should process lost bets correctly", async function () {
            // Get initial balances before spin
            const preSpinPlayerBalance = await treasury.getPlayerBalance(addr1.address);
            const preSpinHouseFunds = await treasury.getHouseFunds();
            const preBetTreasuryBalance = await ethers.provider.getBalance(treasury.getAddress());
            
            // Only spin, bet is already placed in beforeEach
            await roulette.connect(addr1).spinWheel();
            
            const finalPlayerBalance = await treasury.getPlayerBalance(addr1.address);
            const finalHouseFunds = await treasury.getHouseFunds();
            const finalTreasuryBalance = await ethers.provider.getBalance(treasury.getAddress());
            
            // Player's balance should decrease by bet amount (only once)
            expect(finalPlayerBalance).to.equal(preSpinPlayerBalance - betAmount);
            
            // House funds should increase by bet amount (only once)
            expect(finalHouseFunds).to.equal(preSpinHouseFunds + betAmount);
            
            // Treasury's actual ETH balance should increase by bet amount
            expect(finalTreasuryBalance).to.equal(preBetTreasuryBalance);
            
            // Verify roulette contract has no ETH balance
            expect(await ethers.provider.getBalance(roulette.getAddress())).to.equal(0);
        });

        it("Should process winning bets correctly", async function () {
            let win = false;
            let attempts = 0;
            const maxAttempts = 20;
            
            while (!win && attempts < maxAttempts) {
                // Get balances before spin
                const preSpinPlayerBalance = await treasury.getPlayerBalance(addr1.address);
                const preSpinHouseFunds = await treasury.getHouseFunds();
                
                // Spin the wheel (bet already placed in beforeEach)
                const spinTx = await roulette.connect(addr1).spinWheel();
                const receipt = await spinTx.wait();
                
                // Find GameResult event
                const gameResultEvent = receipt.logs.find(
                    log => log.fragment?.name === "GameResult"
                );
                
                if (gameResultEvent && gameResultEvent.args.won) {
                    win = true;
                    
                    const finalPlayerBalance = await treasury.getPlayerBalance(addr1.address);
                    const finalHouseFunds = await treasury.getHouseFunds();
                    
                    // Player should receive 35x their bet (plus original bet)
                    const expectedWinnings = betAmount * BigInt(36);
                    
                    // Player's final balance should be:
                    // Initial balance + winnings
                    expect(finalPlayerBalance).to.equal(
                        preSpinPlayerBalance + expectedWinnings
                    );
                    
                    // House funds should be:
                    // Initial funds - winnings
                    expect(finalHouseFunds).to.equal(
                        preSpinHouseFunds - expectedWinnings
                    );
                    break;
                }
                
                // If no win, place another bet for next attempt
                await roulette.connect(addr1).placeBet([17], { value: betAmount });
                attempts++;
            }
            
            expect(win, "No winning spin found in 20 attempts").to.be.true;
        });

        it("Should update player net winnings correctly", async function () {
            const initialNetWinnings = await treasury.getPlayerNetWinnings(addr1.address);
            await roulette.connect(addr1).spinWheel();
            const finalNetWinnings = await treasury.getPlayerNetWinnings(addr1.address);
            
            // Net winnings should be updated (either positive or negative)
            expect(finalNetWinnings).to.not.equal(initialNetWinnings);
        });
    });

    describe("Administrative Functions", function () {
        it("Should allow owner to pause contract", async function () {
            await roulette.connect(owner).pause();
            await expect(
                roulette.connect(addr1).placeBet([17], { value: minBetAmount })
            ).to.be.revertedWith("Contract is paused");
        });

        it("Should allow owner to unpause contract", async function () {
            await roulette.connect(owner).pause();
            await roulette.connect(owner).unpause();
            await roulette.connect(addr1).placeBet([17], { value: minBetAmount });
            const bets = await roulette.getPlayerBets(addr1.address);
            expect(bets.length).to.equal(1);
        });

        it("Should prevent non-owners from pausing", async function () {
            await expect(
                roulette.connect(addr1).pause()
            ).to.be.revertedWith("Only owner can call this function.");
        });

        it("Should allow owner to set action cooldown", async function () {
            const newCooldown = 60;  // 60 seconds
            await roulette.connect(owner).setActionCooldown(newCooldown);
            // Note: We can't easily test the cooldown effect in a test environment
        });
    });
});