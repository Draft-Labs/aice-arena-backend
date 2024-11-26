require("@nomiclabs/hardhat-waffle");

module.exports = {
  solidity: "0.8.0",
  networks: {
    avalancheFujiTestnet: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: ["770e2955ee27b79282935e6cece716f96b0fa784290a1f6262c02f95992b5c40"] // Replace with your wallet private key
    },
    avalancheMainnet: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      accounts: ["770e2955ee27b79282935e6cece716f96b0fa784290a1f6262c02f95992b5c40"] // Replace with your wallet private key
    },
  }
};
