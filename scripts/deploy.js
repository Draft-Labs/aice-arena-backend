const hre = require("hardhat");

async function main() {
  // Configure the provider to connect to the hosted network
  const provider = new hre.ethers.JsonRpcProvider("http://0.0.0.0:8545");
  
  // Get the deployer's signer
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", await deployer.getAddress());

  // Deploy Treasury
  const HouseTreasury = await hre.ethers.getContractFactory("HouseTreasury");
  const treasury = await HouseTreasury.deploy();
  await treasury.waitForDeployment();
  console.log("Treasury deployed to:", await treasury.getAddress());

  // Deploy Games
  const minBetAmount = hre.ethers.parseEther("0.01");
  const treasuryAddress = await treasury.getAddress();

  const Blackjack = await hre.ethers.getContractFactory("Blackjack");
  const blackjack = await Blackjack.deploy(minBetAmount, treasuryAddress);
  await blackjack.waitForDeployment();
  console.log("Blackjack deployed to:", await blackjack.getAddress());

  const Roulette = await hre.ethers.getContractFactory("Roulette");
  const roulette = await Roulette.deploy(minBetAmount, treasuryAddress);
  await roulette.waitForDeployment();
  console.log("Roulette deployed to:", await roulette.getAddress());

  // Deploy Poker
  const Poker = await hre.ethers.getContractFactory("Poker");
  const poker = await Poker.deploy(minBetAmount, treasuryAddress);
  await poker.waitForDeployment();
  console.log("Poker deployed to:", await poker.getAddress());

  // Authorize games in treasury
  console.log("Authorizing games in treasury...");
  
  // Check and authorize Blackjack
  const blackjackAuthorized = await treasury.authorizedGames(await blackjack.getAddress());
  if (!blackjackAuthorized) {
    try {
      const blackjackTx = await treasury.authorizeGame(await blackjack.getAddress());
      await blackjackTx.wait();
      console.log("Blackjack authorized in treasury");
    } catch (error) {
      console.error("Error authorizing Blackjack:", error);
    }
  }

  // Check and authorize Roulette
  const rouletteAuthorized = await treasury.authorizedGames(await roulette.getAddress());
  if (!rouletteAuthorized) {
    try {
      const rouletteTx = await treasury.authorizeGame(await roulette.getAddress());
      await rouletteTx.wait();
      console.log("Roulette authorized in treasury");
    } catch (error) {
      console.error("Error authorizing Roulette:", error);
    }
  }

  // Check and authorize Poker
  const pokerAuthorized = await treasury.authorizedGames(await poker.getAddress());
  if (!pokerAuthorized) {
    try {
      const pokerTx = await treasury.authorizeGame(await poker.getAddress());
      await pokerTx.wait();
      console.log("Poker authorized in treasury");
    } catch (error) {
      console.error("Error authorizing Poker:", error);
    }
  }

  // Fund treasury
  console.log("Funding treasury...");
  const fundTx = await treasury.ownerFundTreasury({ value: hre.ethers.parseEther("100") });
  await fundTx.wait();
  console.log("Treasury funded with 100 ETH");

  // Log final setup and verify authorizations
  console.log("\nFinal contract setup:");
  console.log("Treasury address:", await treasury.getAddress());
  console.log("Blackjack address:", await blackjack.getAddress());
  console.log("Roulette address:", await roulette.getAddress());
  console.log("Poker address:", await poker.getAddress());
  
  // Verify final authorizations
  const finalBlackjackAuth = await treasury.authorizedGames(await blackjack.getAddress());
  const finalRouletteAuth = await treasury.authorizedGames(await roulette.getAddress());
  const finalPokerAuth = await treasury.authorizedGames(await poker.getAddress());
  console.log("\nAuthorization status:");
  console.log("Blackjack authorized:", finalBlackjackAuth);
  console.log("Roulette authorized:", finalRouletteAuth);
  console.log("Poker authorized:", finalPokerAuth);
  console.log("Treasury balance:", hre.ethers.formatEther(await treasury.getHouseFunds()), "ETH");

  // Save deployment addresses to a file for the backend
  const fs = require('fs');
  const deploymentInfo = {
    TREASURY_ADDRESS: await treasury.getAddress(),
    BLACKJACK_ADDRESS: await blackjack.getAddress(),
    ROULETTE_ADDRESS: await roulette.getAddress(),
    POKER_ADDRESS: await poker.getAddress()
  };

  fs.writeFileSync(
    '.env.local',
    Object.entries(deploymentInfo)
      .map(([key, value]) => `${key}=${value}`)
      .join('\n')
  );
  console.log("\nDeployment addresses saved to .env.local");
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exitCode = 1;
});