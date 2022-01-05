const { expect } = require("chai");
const { ethers } = require("hardhat");
const TF = require("../artifacts/contracts/TradeFarming.sol/TradeFarming.json");
const tokenTF = require("../artifacts/contracts/interfaces/IERC20.sol/IERC20.json");

const provider = ethers.provider;

async function increaseHours(value) {
    value = value * 3600;
    if (!ethers.BigNumber.isBigNumber(value)) {
        value = ethers.BigNumber.from(value);
    }
    await provider.send('evm_increaseTime', [value.toNumber()]);
    await provider.send('evm_mine');
}

async function getBlockTiemstamp() {
    let block_number, block, block_timestamp;

    block_number = await provider.getBlockNumber();;
    block = await provider.getBlock(block_number);
    block_timestamp = block.timestamp;

    return block_timestamp;
}

describe("Trade Farming Test", function () {
    const ROUTER_ADDRESS = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
    const TF_TOKEN_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F"; // DAI: mainnet
    const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // WETH: mainnet
    const TOKEN_COUNT = "100000";
    const PREVIOUS_VOLUME = ethers.utils.parseUnits(TOKEN_COUNT, 18);
    const PREVIOUS_DAYS = 10;
    const TOTAL_DAYS = 3;

    let TFFactory, factory;
    let USDCoin, rewardToken;
    let TFToken;
    let tradeFarmingAddress, tradeFarming;
    let owner, addr1, addr2;
    let pathTnE, pathEnT;

    before(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        USDCoin = await ethers.getContractFactory("USDCoin")
        rewardToken = await USDCoin.deploy();

        TFFactory = await ethers.getContractFactory("TradeFarmingFactory");
        factory = await TFFactory.deploy();

        await factory.createTnAPair(ROUTER_ADDRESS, TF_TOKEN_ADDRESS, rewardToken.address, PREVIOUS_VOLUME, PREVIOUS_DAYS, TOTAL_DAYS);
        tradeFarmingAddress = await factory.createdContract();
        tradeFarming = new ethers.Contract(tradeFarmingAddress, TF.abi, provider);

        pathTnE = [TF_TOKEN_ADDRESS, WETH_ADDRESS];
        pathEnT = [WETH_ADDRESS, TF_TOKEN_ADDRESS];

        TFToken = new ethers.Contract(TF_TOKEN_ADDRESS, tokenTF.abi, provider);

        await rewardToken.approve(tradeFarming.address, ethers.constants.MaxUint256);
        await tradeFarming.connect(owner).depositRewardTokens(PREVIOUS_VOLUME);
    });

    it("Checks all contracts exists", async function () {
        expect(rewardToken.address).to.be.properAddress;
        expect(factory.address).to.be.properAddress;
        expect(tradeFarming.address).to.be.properAddress;
        expect(TFToken.address).to.be.properAddress;
        
        console.log(Number(ethers.utils.formatEther(await TFToken.balanceOf(addr1.address))));
    });
});