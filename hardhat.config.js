require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers"); 

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.0",
  networks: {
    hardhat: {
      forking: {
        url: "https://eth-mainnet.alchemyapi.io/v2/eVvYny0nUFdpdLRVnLW1lACmXvaJQrq4",
      }
    }
  }
};
