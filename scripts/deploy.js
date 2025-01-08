const hre = require("hardhat");

async function main() {
  // Configure the provider to connect to the hosted network
  const provider = new hre.ethers.JsonRpcProvider("http://0.0.0.0:8545");
  
  // Get the deployer's signer
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", await deployer.getAddress());

  // Deploy Treasury
  const HouseTreasury = await hre.ethers.getContractFactory("HouseTreasury");
  const houseTreasury = await HouseTreasury.deploy();
  await houseTreasury.waitForDeployment();
  console.log("HouseTreasury deployed to:", await houseTreasury.getAddress());

  // Deploy Roulette
  const Roulette = await hre.ethers.getContractFactory("Roulette");
  const roulette = await Roulette.deploy(ethers.ZeroAddress, await houseTreasury.getAddress());
  await roulette.waitForDeployment();
  console.log("Roulette deployed to:", await roulette.getAddress());

  // Deploy Blackjack
  const Blackjack = await hre.ethers.getContractFactory("Blackjack");
  const blackjack = await Blackjack.deploy(ethers.ZeroAddress, await houseTreasury.getAddress());
  await blackjack.waitForDeployment();
  console.log("Blackjack deployed to:", await blackjack.getAddress());

  // Deploy Poker Contracts
  console.log("\nDeploying Poker contracts...");

  // First deploy supporting contracts with temporary zero addresses
  const PokerBetting = await hre.ethers.getContractFactory("PokerBetting");
  const pokerBetting = await PokerBetting.deploy(ethers.ZeroAddress, await houseTreasury.getAddress());
  await pokerBetting.waitForDeployment();
  console.log("PokerBetting deployed to:", await pokerBetting.getAddress());

  const PokerPlayerManager = await hre.ethers.getContractFactory("PokerPlayerManager");
  const pokerPlayerManager = await PokerPlayerManager.deploy(ethers.ZeroAddress);
  await pokerPlayerManager.waitForDeployment();
  console.log("PokerPlayerManager deployed to:", await pokerPlayerManager.getAddress());

  const PokerGameState = await hre.ethers.getContractFactory("PokerGameState");
  const pokerGameState = await PokerGameState.deploy(ethers.ZeroAddress);
  await pokerGameState.waitForDeployment();
  console.log("PokerGameState deployed to:", await pokerGameState.getAddress());

  const PokerTreasury = await hre.ethers.getContractFactory("PokerTreasury");
  const pokerTreasury = await PokerTreasury.deploy(ethers.ZeroAddress, await houseTreasury.getAddress());
  await pokerTreasury.waitForDeployment();
  console.log("PokerTreasury deployed to:", await pokerTreasury.getAddress());

  // Deploy PokerTable with the addresses of supporting contracts
  const PokerTable = await hre.ethers.getContractFactory("PokerTable");
  const pokerTable = await PokerTable.deploy(
    await pokerBetting.getAddress(),
    await pokerPlayerManager.getAddress(),
    await pokerGameState.getAddress(),
    await pokerTreasury.getAddress()
  );
  await pokerTable.waitForDeployment();
  console.log("PokerTable deployed to:", await pokerTable.getAddress());

  // Update supporting contracts with PokerTable address
  console.log("\nUpdating contract references...");
  
  await pokerBetting.setPokerTable(await pokerTable.getAddress());
  console.log("Updated PokerBetting reference");
  
  await pokerPlayerManager.setPokerTable(await pokerTable.getAddress());
  console.log("Updated PokerPlayerManager reference");
  
  await pokerGameState.setPokerTable(await pokerTable.getAddress());
  console.log("Updated PokerGameState reference");
  
  await pokerTreasury.setPokerTable(await pokerTable.getAddress());
  console.log("Updated PokerTreasury reference");

  // Authorize contracts in HouseTreasury
  console.log("\nAuthorizing contracts in HouseTreasury...");
  
  await houseTreasury.authorizeGame(await blackjack.getAddress());
  await houseTreasury.authorizeGame(await roulette.getAddress());
  await houseTreasury.authorizeGame(await pokerTable.getAddress());
  await houseTreasury.authorizeGame(await pokerBetting.getAddress());
  await houseTreasury.authorizeGame(await pokerTreasury.getAddress());
  console.log("All poker contracts authorized in HouseTreasury");

  // Fund treasury
  console.log("\nFunding treasury...");
  const fundTx = await houseTreasury.fundHouseTreasury({ value: hre.ethers.parseEther("100") });
  await fundTx.wait();
  console.log("Treasury funded with 100 ETH");

  // Log final setup
  console.log("\nFinal contract setup:");
  console.log("HouseTreasury:", await houseTreasury.getAddress());
  console.log("Roulette:", await roulette.getAddress());
  console.log("Blackjack:", await blackjack.getAddress());
  console.log("PokerTable:", await pokerTable.getAddress());
  console.log("PokerBetting:", await pokerBetting.getAddress());
  console.log("PokerPlayerManager:", await pokerPlayerManager.getAddress());
  console.log("PokerGameState:", await pokerGameState.getAddress());
  console.log("PokerTreasury:", await pokerTreasury.getAddress());

  // Save deployment addresses
  const fs = require('fs');
  const path = require('path');
  const deploymentInfo = {
    TREASURY_ADDRESS: await houseTreasury.getAddress(),
    BLACKJACK_ADDRESS: await blackjack.getAddress(),
    ROULETTE_ADDRESS: await roulette.getAddress(),
    POKER_TABLE_ADDRESS: await pokerTable.getAddress(),
    POKER_BETTING_ADDRESS: await pokerBetting.getAddress(),
    POKER_PLAYER_MANAGER_ADDRESS: await pokerPlayerManager.getAddress(),
    POKER_GAME_STATE_ADDRESS: await pokerGameState.getAddress(),
    POKER_TREASURY_ADDRESS: await pokerTreasury.getAddress()
  };

  // Create both backend and frontend .env files
  const backendEnvPath = path.join(__dirname, '..', '.env');
  const frontendEnvPath = path.join(__dirname, '..', '..', 'betting-dapp-frontend', '.env');

  const envContent = Object.entries(deploymentInfo)
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');

  // Write to backend .env
  fs.writeFileSync(backendEnvPath, envContent);
  console.log("\nDeployment addresses saved to backend .env");

  // Write to frontend .env
  fs.writeFileSync(frontendEnvPath, envContent);
  console.log("Deployment addresses saved to frontend .env");
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exitCode = 1;
});