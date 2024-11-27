require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { PRIVATE_KEY } = process.env;

module.exports = {
  solidity: "0.8.0",
  networks: {
    avalancheFujiTestnet: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: [PRIVATE_KEY]
    },
    avalancheMainnet: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      accounts: [PRIVATE_KEY]
    },
  }
};
