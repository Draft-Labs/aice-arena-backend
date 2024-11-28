const hre = require("hardhat");

async function main() {
  // Deploy contracts
  const HouseTreasury = await hre.ethers.getContractFactory("HouseTreasury");
  const treasury = await HouseTreasury.deploy();
  await treasury.waitForDeployment();
  
  const minBetAmount = hre.ethers.parseEther("0.01");
  const treasuryAddress = await treasury.getAddress();

  const Blackjack = await hre.ethers.getContractFactory("Blackjack");
  const blackjack = await Blackjack.deploy(minBetAmount, treasuryAddress);
  await blackjack.waitForDeployment();

  const Roulette = await hre.ethers.getContractFactory("Roulette");
  const roulette = await Roulette.deploy(minBetAmount, treasuryAddress);
  await roulette.waitForDeployment();

  const Craps = await hre.ethers.getContractFactory("Craps");
  const craps = await Craps.deploy(minBetAmount, treasuryAddress);
  await craps.waitForDeployment();

  // Authorize games in treasury
  await treasury.authorizeGame(await blackjack.getAddress());
  await treasury.authorizeGame(await roulette.getAddress());
  await treasury.authorizeGame(await craps.getAddress());

  // Log addresses
  const addresses = {
    treasury: await treasury.getAddress(),
    blackjack: await blackjack.getAddress(),
    roulette: await roulette.getAddress(),
    craps: await craps.getAddress()
  };

  console.log("Deployed contract addresses:", addresses);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}); 