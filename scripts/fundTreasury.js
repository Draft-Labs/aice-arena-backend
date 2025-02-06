const hre = require("hardhat");

async function main() {
  const treasuryAddress = "0x4FdBE1E16B8903286764608a7B2f05449F26D88E"; // Your deployed treasury address
  const fundAmount = hre.ethers.parseEther("1"); // Change this to the amount you want to send

  console.log(`\nFunding treasury with ${hre.ethers.formatEther(fundAmount)} AVAX...`);

  try {
    // Get the Treasury contract
    const Treasury = await hre.ethers.getContractFactory("HouseTreasury");
    const treasury = Treasury.attach(treasuryAddress);

    // Send the funding transaction
    const tx = await treasury.fundHouseTreasury({ value: fundAmount });
    console.log("Transaction sent:", tx.hash);
    
    // Wait for confirmation
    await tx.wait();
    
    // Get new balance
    const newBalance = await treasury.getHouseFunds();
    console.log(`\nSuccess! New treasury balance: ${hre.ethers.formatEther(newBalance)} AVAX`);

  } catch (error) {
    console.error("Error funding treasury:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 