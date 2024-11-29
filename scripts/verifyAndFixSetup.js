const hre = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Verifying contracts with account:", deployer.address);

  // Get contract factories
  const Treasury = await ethers.getContractFactory("HouseTreasury");
  const Blackjack = await ethers.getContractFactory("Blackjack");

  // Deploy new contracts if needed
  let treasury, blackjack;

  try {
    treasury = await Treasury.attach("0x5FbDB2315678afecb367f032d93F642f64180aa3");
    await treasury.owner(); // Will throw if contract doesn't exist
    console.log("Treasury contract found");
  } catch (error) {
    console.log("Deploying new Treasury contract...");
    treasury = await Treasury.deploy();
    await treasury.waitForDeployment();
  }

  try {
    blackjack = await Blackjack.attach("0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512");
    await blackjack.owner(); // Will throw if contract doesn't exist
    console.log("Blackjack contract found");
  } catch (error) {
    console.log("Deploying new Blackjack contract...");
    blackjack = await Blackjack.deploy(
      ethers.parseEther("0.01"),
      await treasury.getAddress()
    );
    await blackjack.waitForDeployment();
  }

  // Log contract addresses
  console.log("Contract addresses:");
  console.log("Treasury:", await treasury.getAddress());
  console.log("Blackjack:", await blackjack.getAddress());

  // Verify and fix authorization
  const isAuthorized = await treasury.authorizedGames(await blackjack.getAddress());
  console.log("Current authorization status:", isAuthorized);

  if (!isAuthorized) {
    console.log("Authorizing Blackjack contract...");
    await treasury.authorizeGame(await blackjack.getAddress());
    console.log("Authorization complete");
  }

  // Fund treasury if needed
  const balance = await treasury.getHouseFunds();
  if (balance < ethers.parseEther("10")) {
    console.log("Funding treasury...");
    await treasury.fundHouseTreasury({ value: ethers.parseEther("100") });
    console.log("Treasury funded");
  }

  // Final verification
  console.log("\nFinal contract state:");
  console.log("Treasury balance:", ethers.formatEther(await treasury.getHouseFunds()), "ETH");
  console.log("Blackjack authorized:", await treasury.authorizedGames(await blackjack.getAddress()));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 