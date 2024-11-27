require("dotenv").config();
const { ethers } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying the contracts with the account:", deployer.address);

    // Fetch balance to verify deployment account has funds
    const balance = await deployer.getBalance();
    console.log("Account balance:", ethers.formatEther(balance));

    // Get the Blackjack contract factory
    const Blackjack = await ethers.getContractFactory("Blackjack");

    // Deploy the Blackjack contract (change the minimum bet amount if needed)
    const blackjack = await Blackjack.deploy(ethers.parseEther("0.01"));
    console.log("Blackjack deployed to:", blackjack.address);

    // Get the CrapsGame contract factory
    const CrapsGame = await ethers.getContractFactory("CrapsGame");

    // Deploy the CrapsGame contract
    const crapsGame = await CrapsGame.deploy();
    console.log("CrapsGame deployed to:", crapsGame.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
