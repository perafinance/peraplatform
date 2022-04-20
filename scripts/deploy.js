const { ethers } = require("hardhat");
const tokenTF = require("../artifacts/contracts/Mock_USDCoin.sol/USDCoin.json");
// const tfC = require("../artifacts/contracts/trade-farming/TradeFarmingAVAX.sol/TradeFarmingAVAX.json");
const provider = ethers.provider;

const ROUTER_ADDRESS = "0x5db0735cf88F85E78ed742215090c465979B5006";
const TF_TOKEN_ADDRESS = "0xa9d19d5e8712C1899C4344059FD2D873a3e2697E";
const TOKEN_COUNTA = "200000";
const TOKEN_COUNTB = "100";
const PREVIOUS_VOLUME = ethers.utils.parseUnits(TOKEN_COUNTA, 18);
const REWARDS = ethers.utils.parseUnits(TOKEN_COUNTB, 18);
const PREVIOUS_DAYS = 7;
const TOTAL_DAYS = 7;

const TF_ADDRESS = "0x8f2E6E92764C55b07f6edFE623c01bF253834080";

async function main() {

  let [deployer] = await ethers.getSigners();

  let baseNonce = provider.getTransactionCount(deployer.address);
  let nonceOffset = 0;

  function getNonce() {
    return baseNonce.then((nonce) => (nonce + (nonceOffset++)));
  }

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  let TradeFarming = await ethers.getContractFactory("TradeFarmingAVAX");
  let tf = await TradeFarming.connect(deployer).deploy(ROUTER_ADDRESS, TF_TOKEN_ADDRESS, TF_TOKEN_ADDRESS, PREVIOUS_VOLUME, PREVIOUS_DAYS, TOTAL_DAYS, 100, 100, {nonce: getNonce()});
  
  // let tf = new ethers.Contract(TF_ADDRESS, tfC.abi, deployer);

  console.log("Contract address:", tf.address);

  let token = new ethers.Contract(TF_TOKEN_ADDRESS, tokenTF.abi, provider);
  let tx0 = await token.connect(deployer).approve(tf.address, ethers.constants.MaxUint256, {nonce: getNonce()});
  await tx0.wait();

  let tx1 = await token.connect(deployer).mint(deployer.address, REWARDS, {nonce: getNonce()});
  await tx1.wait();

  let tx2 = await tf.connect(deployer).depositRewardTokens(REWARDS, {nonce: getNonce()});
  await tx2.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });