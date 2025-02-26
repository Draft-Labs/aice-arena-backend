require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "0000000000000000000000000000000000000000000000000000000000000000";

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200
      },
    },
  },
  networks: {
    remote: {
      url: "http://192.168.7.222:8545",
      chainId: 31337
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337
    },
    fuji: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      chainId: 43113,
      accounts: [PRIVATE_KEY],
      gasPrice: "auto",
      verify: {
        etherscan: {
          apiUrl: "https://api-testnet.snowtrace.io/api",
          browserURL: "https://testnet.snowtrace.io",
          apiKey: "YourApiKeyToken"
        }
      }
    }
  },
  etherscan: {
    apiKey: {
      avalancheFujiTestnet: "YourApiKeyToken"
    }
  }
};
