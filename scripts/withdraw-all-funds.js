require('dotenv').config();
const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
  // Configure the provider to connect to Fuji testnet
  const provider = new hre.ethers.JsonRpcProvider(process.env.AVALANCHE_FUJI_RPC_URL);
  
  // Get the deployer's signer using private key
  const deployer = new hre.ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Withdrawing funds with account:", deployer.address);

  // Contract addresses
  const TREASURY_ADDRESS = "0x875F9bC922006Ec89ce55212Fb351f4b3FAfa109";
  const BLACKJACK_ADDRESS = "0x75189f668a08693430632Be3a1f38a2Fbe5038F5";
  const ROULETTE_ADDRESS = "0xcFf96B0578816b96Aec75b3DAb6A185aA9bC2E23";

  // Get contract instances
  const treasury = await hre.ethers.getContractAt("HouseTreasury", TREASURY_ADDRESS, deployer);
  const blackjack = await hre.ethers.getContractAt("Blackjack", BLACKJACK_ADDRESS, deployer);
  const roulette = await hre.ethers.getContractAt("Roulette", ROULETTE_ADDRESS, deployer);

  // Get balances
  const treasuryBalance = await provider.getBalance(TREASURY_ADDRESS);
  const blackjackBalance = await provider.getBalance(BLACKJACK_ADDRESS);
  const rouletteBalance = await provider.getBalance(ROULETTE_ADDRESS);

  console.log("Initial balances:");
  console.log("Treasury:", ethers.formatEther(treasuryBalance), "AVAX");
  console.log("Blackjack:", ethers.formatEther(blackjackBalance), "AVAX");
  console.log("Roulette:", ethers.formatEther(rouletteBalance), "AVAX");

  try {
    // Withdraw from Treasury
    if (treasuryBalance > 0) {
      console.log("\nWithdrawing from Treasury...");
      const houseFunds = await treasury.getHouseFunds();
      const tx = await treasury.withdrawHouseFunds(houseFunds, {
        gasLimit: 500000
      });
      await tx.wait();
      console.log("Treasury withdrawal complete");
    }

    // Add delay between transactions
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Get final balances
    const finalTreasuryBalance = await provider.getBalance(TREASURY_ADDRESS);
    const finalBlackjackBalance = await provider.getBalance(BLACKJACK_ADDRESS);
    const finalRouletteBalance = await provider.getBalance(ROULETTE_ADDRESS);

    console.log("\nFinal balances:");
    console.log("Treasury:", ethers.formatEther(finalTreasuryBalance), "AVAX");
    console.log("Blackjack:", ethers.formatEther(finalBlackjackBalance), "AVAX");
    console.log("Roulette:", ethers.formatEther(finalRouletteBalance), "AVAX");

  } catch (error) {
    console.error("Error during withdrawal:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 