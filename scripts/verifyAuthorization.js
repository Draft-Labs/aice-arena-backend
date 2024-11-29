const hre = require("hardhat");

async function main() {
  const [owner] = await ethers.getSigners();

  // Get contract factories
  const Treasury = await ethers.getContractFactory("HouseTreasury");
  const Blackjack = await ethers.getContractFactory("Blackjack");

  // Get deployed contract addresses
  const treasuryAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
  const blackjackAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512";

  // Get contract instances
  const treasury = Treasury.attach(treasuryAddress);
  const blackjack = Blackjack.attach(blackjackAddress);

  console.log("Checking authorization...");
  const isAuthorized = await treasury.authorizedGames(blackjackAddress);
  console.log("Current authorization status:", isAuthorized);

  if (!isAuthorized) {
    console.log("Authorizing Blackjack contract...");
    const tx = await treasury.connect(owner).authorizeGame(blackjackAddress);
    await tx.wait();
    console.log("Authorization complete. New status:", await treasury.authorizedGames(blackjackAddress));
  }

  // Fund treasury if needed
  const houseFunds = await treasury.getHouseFunds();
  if (houseFunds < ethers.parseEther("10")) {
    console.log("Funding treasury...");
    const tx = await treasury.connect(owner).fundHouseTreasury({ 
      value: ethers.parseEther("100") 
    });
    await tx.wait();
    console.log("Treasury funded. New balance:", 
      ethers.formatEther(await treasury.getHouseFunds()), "ETH"
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 