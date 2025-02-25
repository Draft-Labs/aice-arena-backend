const hre = require("hardhat");

async function main() {
  // Determine network
  const network = hre.network.name;
  console.log(`Starting deployment to ${network}...`);

  // Get the deployer's signer
  const [deployer] = await hre.ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  const deployerBalance = await deployer.provider.getBalance(deployerAddress);

  console.log("Deploying contracts with account:", deployerAddress);
  console.log("Account balance:", hre.ethers.formatEther(deployerBalance), 
    network === 'fuji' ? "AVAX" : "ETH");

  try {
    // Deploy Treasury
    console.log("\nDeploying Treasury...");
    const HouseTreasury = await hre.ethers.getContractFactory("HouseTreasury");
    const treasury = await HouseTreasury.deploy();
    await treasury.waitForDeployment();
    console.log("Treasury deployed to:", await treasury.getAddress());

    // Deploy Games
    const minBetAmount = hre.ethers.parseEther("0.1"); // 0.1 AVAX minimum bet
    const treasuryAddress = await treasury.getAddress();

    console.log("\nDeploying Blackjack...");
    const Blackjack = await hre.ethers.getContractFactory("Blackjack");
    const blackjack = await Blackjack.deploy(minBetAmount, treasuryAddress);
    await blackjack.waitForDeployment();
    console.log("Blackjack deployed to:", await blackjack.getAddress());

    console.log("\nDeploying Roulette...");
    const Roulette = await hre.ethers.getContractFactory("Roulette");
    const roulette = await Roulette.deploy(minBetAmount, treasuryAddress);
    await roulette.waitForDeployment();
    console.log("Roulette deployed to:", await roulette.getAddress());

    console.log("\nDeploying Poker...");
    const Poker = await hre.ethers.getContractFactory("Poker");
    const poker = await Poker.deploy(minBetAmount, treasuryAddress);
    await poker.waitForDeployment();
    console.log("Poker deployed to:", await poker.getAddress());

    // Authorize games in treasury with error handling
    console.log("\nAuthorizing games in treasury...");
    
    const authorizeGame = async (game, gameName) => {
      const gameAddress = await game.getAddress();
      const isAuthorized = await treasury.authorizedGames(gameAddress);
      
      if (!isAuthorized) {
        try {
          const tx = await treasury.authorizeGame(gameAddress);
          await tx.wait();
          console.log(`${gameName} authorized in treasury`);
        } catch (error) {
          console.error(`Error authorizing ${gameName}:`, error.message);
          throw error;
        }
      } else {
        console.log(`${gameName} already authorized`);
      }
    };

    await authorizeGame(blackjack, "Blackjack");
    await authorizeGame(roulette, "Roulette");
    await authorizeGame(poker, "Poker");

    // Fund treasury
    console.log("\nFunding treasury...");
    try {
      const fundAmount = hre.ethers.parseEther("1"); // Fund with 1 AVAX for testnet
      const fundTx = await treasury.fundHouseTreasury({ value: fundAmount });
      await fundTx.wait();
      console.log(`Treasury funded with ${hre.ethers.formatEther(fundAmount)} AVAX`);
    } catch (error) {
      console.error("Error funding treasury:", error.message);
    }

    // Save deployment addresses
    const deploymentInfo = {
      NETWORK: network,
      TREASURY_ADDRESS: await treasury.getAddress(),
      BLACKJACK_ADDRESS: await blackjack.getAddress(),
      ROULETTE_ADDRESS: await roulette.getAddress(),
      POKER_ADDRESS: await poker.getAddress(),
      DEPLOYMENT_TIMESTAMP: new Date().toISOString()
    };

    // Save to environment file based on network
    const fs = require('fs');
    const envFile = network === 'fuji' ? '.env.fuji' : '.env.local';
    
    // Create REACT_APP_ prefixed environment variables
    const reactEnvVars = {
      REACT_APP_NETWORK: network,
      REACT_APP_RPC_URL: network === 'fuji' 
        ? "https://api.avax-test.network/ext/bc/C/rpc"
        : "http://127.0.0.1:8545",
      REACT_APP_CHAIN_ID: network === 'fuji' ? "43113" : "31337",
      REACT_APP_TREASURY_ADDRESS: deploymentInfo.TREASURY_ADDRESS,
      REACT_APP_BLACKJACK_ADDRESS: deploymentInfo.BLACKJACK_ADDRESS,
      REACT_APP_ROULETTE_ADDRESS: deploymentInfo.ROULETTE_ADDRESS,
      REACT_APP_POKER_ADDRESS: deploymentInfo.POKER_ADDRESS
    };

    // Save to environment file
    fs.writeFileSync(
      envFile,
      Object.entries(reactEnvVars)
        .map(([key, value]) => `${key}=${value}`)
        .join('\n')
    );

    // Save to deployments log
    const deploymentLog = `deployments/${network}-${Date.now()}.json`;
    fs.mkdirSync('deployments', { recursive: true });
    fs.writeFileSync(
      deploymentLog,
      JSON.stringify(deploymentInfo, null, 2)
    );

    console.log("\nDeployment Summary:");
    console.log("===================");
    console.log(`Network: ${network}`);
    console.log("Treasury:", await treasury.getAddress());
    console.log("Blackjack:", await blackjack.getAddress());
    console.log("Roulette:", await roulette.getAddress());
    console.log("Poker:", await poker.getAddress());
    console.log("\nDeployment addresses saved to:", deploymentLog);
    
    // Verify final state
    const treasuryBalance = await treasury.getHouseFunds();
    console.log("\nFinal Treasury Balance:", hre.ethers.formatEther(treasuryBalance), 
      network === 'fuji' ? "AVAX" : "ETH");

  } catch (error) {
    console.error("\nDeployment failed:", error);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error("\nFatal error:", error);
  process.exitCode = 1;
});