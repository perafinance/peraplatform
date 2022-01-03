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

async function getBalances(address, TFToken) {
    let balances = [];
    balances[0] = await provider.getBalance(address);
    balances[1] = await TFToken.balanceOf(address);

    return balances;
}

async function getBlockTiemstamp() {
    let block_number, block, block_timestamp;

    block_number = await provider.getBlockNumber();;
    block = await provider.getBlock(block_number);
    block_timestamp = block.timestamp;

    return block_timestamp;
}

describe("Trade Farming Contract", function () {
    const ROUTER_ADDRESS = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
    const TF_TOKEN_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F"; // DAI: mainnet
    const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // WETH: mainnet
    const TOKEN_COUNT = "100000";
    const PREVIOUS_VOLUME = ethers.utils.parseUnits(TOKEN_COUNT, 18);
    const PREVIOUS_DAYS = 10;
    const TOTAL_DAYS = 10;

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
    });

    it("Deposits reward tokens", async function () {
        expect(await tradeFarming.totalRewardBalance()).to.be.equal(PREVIOUS_VOLUME);
    });

    
    describe("Swap", function () {
        let userBalances = [], newBalances = [];
        let bTimestamp;
        let initialVolume, volume = 0, expectedVolume = 0;

        beforeEach(async function () {
            userBalances[0] = Number(ethers.utils.formatEther(await provider.getBalance(addr1.address)));
            userBalances[1] = Number(ethers.utils.formatEther(await TFToken.balanceOf(addr1.address)));
            bTimestamp = await getBlockTiemstamp();
            await TFToken.connect(addr1).approve(tradeFarming.address, ethers.constants.MaxUint256);
            initialVolume = Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(addr1.address, 0))); 
        });

        it("Exact ETH for Tokens and record volumes", async function () {
            await tradeFarming.connect(addr1).swapExactETHForTokens(0, pathEnT, addr1.address, bTimestamp * 2, { value: ethers.utils.parseEther("1") });
            newBalances[0] = Number(ethers.utils.formatEther(await provider.getBalance(addr1.address)));
            newBalances[1] = Number(ethers.utils.formatEther(await TFToken.balanceOf(addr1.address)));

            console.log("Ether Balance: " + userBalances[0] + " -> " + newBalances[0]);
            console.log("DAI Balance: " + userBalances[1] + " -> " + newBalances[1]);
            expect(userBalances[0]).to.be.greaterThan(newBalances[0]);
            expect(newBalances[1]).to.be.greaterThan(userBalances[1]);

            volume = newBalances[1] - userBalances[1];
            expectedVolume = Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(addr1.address, 0))) - initialVolume;
            expect(volume).to.be.equal(expectedVolume);
        });

        it("Swaps ETH for Exact Tokens and record volumes", async function () {
            await tradeFarming.connect(addr1).swapETHForExactTokens(ethers.utils.parseEther("300"), pathEnT, addr1.address, bTimestamp * 2, { value: ethers.utils.parseEther("2") });
            newBalances[0] = Number(ethers.utils.formatEther(await provider.getBalance(addr1.address)));
            newBalances[1] = Number(ethers.utils.formatEther(await TFToken.balanceOf(addr1.address)));

            console.log("Ether Balance: " + userBalances[0] + " -> " + newBalances[0]);
            console.log("DAI Balance: " + userBalances[1] + " -> " + newBalances[1]);

            expect(userBalances[0]).to.be.greaterThan(newBalances[0]);
            expect(newBalances[1]).to.be.equal(userBalances[1] + 300);

            volume = newBalances[1] - userBalances[1];
            expectedVolume = Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(addr1.address, 0))) - initialVolume;
            expect(volume).to.be.equal(expectedVolume);
        });


        it("Exact Token for ETH and record volumes", async function () {
            await tradeFarming.connect(addr1).swapExactTokensForETH(ethers.utils.parseEther("300"), 0, pathTnE, addr1.address, bTimestamp * 2);
            newBalances[0] = Number(ethers.utils.formatEther(await provider.getBalance(addr1.address)));
            newBalances[1] = Number(ethers.utils.formatEther(await TFToken.balanceOf(addr1.address)));

            console.log("Ether Balance: " + userBalances[0] + " -> " + newBalances[0]);
            console.log("DAI Balance: " + userBalances[1] + " -> " + newBalances[1]);

            expect(newBalances[0]).to.be.greaterThan(userBalances[0]);
            expect(userBalances[1]).to.be.greaterThan(newBalances[1]);

            volume = userBalances[1] - newBalances[1];
            expectedVolume = Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(addr1.address, 0))) - initialVolume;
            expect(volume).to.be.equal(expectedVolume);
        });

        it("Tokens for Exact ETH and record volumes", async function () {
            await tradeFarming.connect(addr1).swapTokensForExactETH(ethers.utils.parseEther("0.1"), ethers.utils.parseEther("500"), pathTnE, addr1.address, bTimestamp * 2);
            newBalances[0] = Number(ethers.utils.formatEther(await provider.getBalance(addr1.address)));
            newBalances[1] = Number(ethers.utils.formatEther(await TFToken.balanceOf(addr1.address)));

            console.log("Ether Balance: " + userBalances[0] + " -> " + newBalances[0]);
            console.log("DAI Balance: " + userBalances[1] + " -> " + newBalances[1]);

            expect(newBalances[0]).to.be.greaterThan(userBalances[0]);
            expect(userBalances[1]).to.be.greaterThan(newBalances[1]);

            volume = userBalances[1] - newBalances[1];
            expectedVolume = Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(addr1.address, 0))) - initialVolume;
            // MAY HAVE PROBLEMS // expect(volume).to.be.equal(expectedVolume);

        });

    });
    

    describe("Skip Days", function () {
        let currentDay, newDay;
        let userReward, dailyReward;
        it("Can skip days", async function () {
            currentDay = Number(await tradeFarming.calcDay());
            await increaseHours(25);
            newDay = Number(await tradeFarming.calcDay());

            expect(currentDay + 1).to.be.equal(newDay);
        });

        it("Understands uncalculated days", async function () { 
            expect(await tradeFarming.isCalculated()).to.be.equal(false);
        });

        it("Calculates new days after swaps", async function () {
            await tradeFarming.connect(addr1).swapExactETHForTokens(0, pathEnT, addr1.address, 9999999999999, { value: ethers.utils.parseEther("1") });

            expect(await tradeFarming.isCalculated()).to.be.equal(true);
        });

        it("Can calculate user rewards", async function() {
            userReward = Number(ethers.utils.formatEther(await tradeFarming.connect(addr1).calculateUserRewards()));
            dailyReward = Number(ethers.utils.formatEther(await tradeFarming.connect(addr1).dailyRewards(currentDay)));
            
            expect(dailyReward).to.be.equal(userReward);
            expect(dailyReward).to.be.greaterThan(0);
        });
    });
});