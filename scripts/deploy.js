const { ethers } = require("hardhat");
const tokenTF = require("../artifacts/contracts/interfaces/IERC20.sol/IERC20.json");
const provider = ethers.provider;

const ROUTER_ADDRESS = "0x2D99ABD9008Dc933ff5c0CD271B88309593aB921";
const TF_TOKEN_ADDRESS = "0x2292b53701C119bB7ee2437214dB5E101B7B780c";
const TOKEN_COUNT = "30000000";
const PREVIOUS_VOLUME = ethers.utils.parseUnits(TOKEN_COUNT, 18);
const PREVIOUS_DAYS = 10;
const TOTAL_DAYS = 7;

async function main() {

    let [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    let TradeFarming = await ethers.getContractFactory("TradeFarmingAVAX");
    let tf = await TradeFarming.deploy(ROUTER_ADDRESS, TF_TOKEN_ADDRESS, TF_TOKEN_ADDRESS, PREVIOUS_VOLUME, PREVIOUS_DAYS, TOTAL_DAYS);
    console.log("Contract address:", tf.address);

    let token = new ethers.Contract(TF_TOKEN_ADDRESS, tokenTF.abi, provider);
    let tx0 = await token.connect(deployer).approve(tf.address, ethers.constants.MaxUint256);
    await tx0.wait();
    let tx1 = await tf.connect(deployer).depositRewardTokens(PREVIOUS_VOLUME);
    await tx1.wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });