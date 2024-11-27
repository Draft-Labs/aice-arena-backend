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
  await treasury.authorizeGame(await blackjack.getAddress());
  await treasury.authorizeGame(await roulette.getAddress());
  await treasury.authorizeGame(await craps.getAddress());
  console.log("Games authorized in treasury");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});