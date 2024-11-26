async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying the contract with the account:", deployer.address);

    // Fetch balance to verify deployment account has funds
    const balance = await deployer.getBalance();
    console.log("Account balance:", ethers.utils.formatEther(balance));

    // Get the contract factory
    const Blackjack = await ethers.getContractFactory("Blackjack");

    // Deploy contract (change the minimum bet amount if needed)
    const blackjack = await BettingBlackjack.deploy(ethers.utils.parseEther("0.01"));

    // Wait for deployment to finish
    await blackjack.deployed();

    console.log("Blackjack deployed to:", blackjack.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
