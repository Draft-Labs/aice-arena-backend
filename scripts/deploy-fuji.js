const hre = require("hardhat");
require("dotenv").config();

async function main() {
  // Configure the provider to connect to Fuji testnet
  const provider = new hre.ethers.JsonRpcProvider(process.env.AVALANCHE_FUJI_RPC_URL);
  
  // Get the deployer's signer using private key
  const deployer = new hre.ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Deploying contracts with account:", deployer.address);
  
  // Log initial balance
  const initialBalance = await provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(initialBalance), "AVAX");

  // Deploy Treasury with higher gas limit for Avalanche
  const HouseTreasury = await hre.ethers.getContractFactory("HouseTreasury", deployer);
  const treasury = await HouseTreasury.deploy({
    gasLimit: 8000000
  });
  await treasury.waitForDeployment();
  console.log("Treasury deployed to:", await treasury.getAddress());

  // Deploy Games with appropriate min bet for testnet (0.01 AVAX)
  const minBetAmount = hre.ethers.parseEther("0.01");
  const treasuryAddress = await treasury.getAddress();

  // Deploy Blackjack
  const Blackjack = await hre.ethers.getContractFactory("Blackjack", deployer);
  const blackjack = await Blackjack.deploy(
    minBetAmount, 
    treasuryAddress,
    { gasLimit: 8000000 }
  );
  await blackjack.waitForDeployment();
  console.log("Blackjack deployed to:", await blackjack.getAddress());

  // Deploy Roulette
  const Roulette = await hre.ethers.getContractFactory("Roulette", deployer);
  const roulette = await Roulette.deploy(
    minBetAmount, 
    treasuryAddress,
    { gasLimit: 8000000 }
  );
  await roulette.waitForDeployment();
  console.log("Roulette deployed to:", await roulette.getAddress());

  // Add delay between transactions for Avalanche
  const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  await delay(2000); // 2 second delay

  // Authorize games with higher gas limits
  console.log("Authorizing games in treasury...");
  
  // Authorize Blackjack
  const blackjackTx = await treasury.authorizeGame(
    await blackjack.getAddress(),
    { gasLimit: 8000000 }
  );
  await blackjackTx.wait();
  console.log("Blackjack authorized in treasury");
  await delay(2000);

  // Authorize Roulette
  const rouletteTx = await treasury.authorizeGame(
    await roulette.getAddress(),
    { gasLimit: 8000000 }
  );
  await rouletteTx.wait();
  console.log("Roulette authorized in treasury");
  await delay(2000);

  // Fund treasury with 10 AVAX for testnet
  console.log("Funding treasury...");
  const fundTx = await treasury.fundHouseTreasury({ 
    value: hre.ethers.parseEther("10"),
    gasLimit: 8000000
  });
  await fundTx.wait();
  console.log("Treasury funded with 10 AVAX");

  // Save deployment addresses and attempt verification
  const deploymentInfo = {
    NETWORK: "fuji",
    TREASURY_ADDRESS: await treasury.getAddress(),
    BLACKJACK_ADDRESS: await blackjack.getAddress(),
    ROULETTE_ADDRESS: await roulette.getAddress(),
    VERIFICATION_STATUS: "unverified"
  };

  // Save to both .env.fuji and deployments.txt
  const fs = require('fs');
  
  // Attempt verification if SNOWTRACE_API_KEY is present
  if (process.env.SNOWTRACE_API_KEY) {
    console.log("\nAttempting contract verification on Snowtrace...");
    try {
      const contracts = [
        {
          name: "Treasury",
          address: deploymentInfo.TREASURY_ADDRESS,
          args: []
        },
        {
          name: "Blackjack",
          address: deploymentInfo.BLACKJACK_ADDRESS,
          args: [minBetAmount, treasuryAddress]
        },
        {
          name: "Roulette",
          address: deploymentInfo.ROULETTE_ADDRESS,
          args: [minBetAmount, treasuryAddress]
        }
      ];

      for (const contract of contracts) {
        try {
          await hre.run("verify:verify", {
            address: contract.address,
            constructorArguments: contract.args
          });
          console.log(`✅ ${contract.name} verified successfully`);
        } catch (error) {
          console.error(`❌ Failed to verify ${contract.name}:`, error.message);
        }
        // Add delay between verifications
        await delay(2000);
      }
      deploymentInfo.VERIFICATION_STATUS = "verified";
    } catch (error) {
      console.error("Error during contract verification:", error);
      deploymentInfo.VERIFICATION_STATUS = "failed";
    }
  } else {
    console.log("\nSkipping contract verification (no SNOWTRACE_API_KEY)");
  }

  // Save final deployment info
  fs.writeFileSync(
    '.env.fuji',
    Object.entries(deploymentInfo)
      .map(([key, value]) => `${key}=${value}`)
      .join('\n')
  );

  const deploymentText = `\n# Avalanche Fuji Testnet Deployment ${new Date().toISOString()}\n` +
    `Treasury: ${deploymentInfo.TREASURY_ADDRESS}\n` +
    `Blackjack: ${deploymentInfo.BLACKJACK_ADDRESS}\n` +
    `Roulette: ${deploymentInfo.ROULETTE_ADDRESS}\n` +
    `Verification Status: ${deploymentInfo.VERIFICATION_STATUS}\n`;

  fs.appendFileSync('deployments.txt', deploymentText);

  console.log("\nDeployment Complete!");
  console.log("Deployment addresses saved to .env.fuji and deployments.txt");
}

main().catch((error) => {
  console.error("Deployment failed:", error);
  process.exitCode = 1;
}); 