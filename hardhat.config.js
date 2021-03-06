require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
const private_key = require("./keys/privatekey.json");


const PRIVATE_KEY = private_key.key;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: { version: "0.8.2", settings: { optimizer: { enabled: true, runs: 200 } } },
  networks: {
    hardhat: {
      forking: {
        url: "https://eth-mainnet.alchemyapi.io/v2/eVvYny0nUFdpdLRVnLW1lACmXvaJQrq4",
      }
    },
    fuji: {
      url: `https://api.avax-test.network/ext/bc/C/rpc`,
      accounts: [`${PRIVATE_KEY}`]
    },
    mainnet: {
      url: `https://api.avax.network/ext/bc/C/rpc`,
      accounts: [`${PRIVATE_KEY}`]
    }
  }
};
