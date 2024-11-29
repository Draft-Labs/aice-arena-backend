const hre = require("hardhat");

async function main() {
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

  const Craps = await hre.ethers.getContractFactory("Craps");
  const craps = await Craps.deploy(minBetAmount, treasuryAddress);
  await craps.waitForDeployment();
  console.log("Craps deployed to:", await craps.getAddress());

  // Authorize games in treasury
  console.log("Authorizing games in treasury...");
  
  // Check current authorization
  const blackjackAuthorized = await treasury.authorizedGames(await blackjack.getAddress());
  if (!blackjackAuthorized) {
    await treasury.authorizeGame(await blackjack.getAddress());
    console.log("Blackjack authorized in treasury");
  }

  // Fund treasury
  console.log("Funding treasury...");
  await treasury.fundHouseTreasury({ value: ethers.parseEther("100") });
  console.log("Treasury funded with 100 ETH");

  // Log final setup
  console.log("Final contract setup:");
  console.log("Treasury address:", await treasury.getAddress());
  console.log("Blackjack address:", await blackjack.getAddress());
  console.log("Blackjack authorized:", await treasury.authorizedGames(await blackjack.getAddress()));
  console.log("Treasury balance:", ethers.formatEther(await treasury.getHouseFunds()), "ETH");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});