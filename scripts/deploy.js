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

  // Fund treasury
  console.log("Funding treasury...");
  const fundTx = await treasury.fundHouseTreasury({ value: hre.ethers.parseEther("100") });
  await fundTx.wait();
  console.log("Treasury funded with 100 ETH");

  // Log final setup and verify authorizations
  console.log("\nFinal contract setup:");
  console.log("Treasury address:", await treasury.getAddress());
  console.log("Blackjack address:", await blackjack.getAddress());
  console.log("Roulette address:", await roulette.getAddress());
  
  // Verify final authorizations
  const finalBlackjackAuth = await treasury.authorizedGames(await blackjack.getAddress());
  const finalRouletteAuth = await treasury.authorizedGames(await roulette.getAddress());
  console.log("\nAuthorization status:");
  console.log("Blackjack authorized:", finalBlackjackAuth);
  console.log("Roulette authorized:", finalRouletteAuth);
  console.log("Treasury balance:", hre.ethers.formatEther(await treasury.getHouseFunds()), "ETH");

  // Save deployment addresses to a file for the backend
  const fs = require('fs');
  const deploymentInfo = {
    TREASURY_ADDRESS: await treasury.getAddress(),
    BLACKJACK_ADDRESS: await blackjack.getAddress(),
    ROULETTE_ADDRESS: await roulette.getAddress()
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
  console.error(error);
  process.exitCode = 1;
});