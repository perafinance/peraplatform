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

function expectArgsEqual() {
    let args = [...arguments]
    for (i = 0; i < args.length - 1; i++) {
        expect(args[i]).to.be.equal(args[i + 1]);
    }
}

describe("Trade Farming Test", function () {
    const ROUTER_ADDRESS = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
    const TF_TOKEN_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F"; // DAI: mainnet
    const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"; // WETH: mainnet
    const TOKEN_COUNT = "3000";
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

    describe("Trade Farming", function () {
        let bTimestamp, currentDay;
        let total_volumes = 0;
        let initial_balances = [];
        let daily_volumes = [];
        let reward_balances = [], new_reward_balances = [];

        before(async function () {
            await TFToken.connect(owner).approve(tradeFarming.address, ethers.constants.MaxUint256);
            await TFToken.connect(addr1).approve(tradeFarming.address, ethers.constants.MaxUint256);
            await TFToken.connect(addr2).approve(tradeFarming.address, ethers.constants.MaxUint256);
        });

        beforeEach(async function () {
            bTimestamp = await getBlockTiemstamp();
            currentDay = Number(await tradeFarming.calcDay());

            initial_balances[0] = Math.ceil(Number(ethers.utils.formatEther(await TFToken.balanceOf(owner.address))));
            initial_balances[1] = Math.ceil(Number(ethers.utils.formatEther(await TFToken.balanceOf(addr1.address))));
            initial_balances[2] = Math.ceil(Number(ethers.utils.formatEther(await TFToken.balanceOf(addr2.address))));

            reward_balances[0] = Math.ceil(Number(ethers.utils.formatEther(await rewardToken.balanceOf(owner.address))));
            reward_balances[1] = Math.ceil(Number(ethers.utils.formatEther(await rewardToken.balanceOf(addr1.address))));
            reward_balances[2] = Math.ceil(Number(ethers.utils.formatEther(await rewardToken.balanceOf(addr2.address))));

        });

        it("Day#0", async function () {
            let amountsIn;
            let volumes = ["1000", "1000", "1000"];
            let balances = [];
            let daily_records = [];

            total_volumes += Number(volumes[0]) + Number(volumes[1]) + Number(volumes[2]);

            amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volumes[0]), pathTnE);
            await tradeFarming.connect(owner).swapETHForExactTokens(ethers.utils.parseEther(volumes[0]), pathEnT, owner.address, bTimestamp * 2, { value: amountsIn[1] });
            balances[0] = Math.ceil(Number(ethers.utils.formatEther(await TFToken.balanceOf(owner.address))));
            daily_records[0] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(owner.address, currentDay))));

            amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volumes[1]), pathTnE);
            await tradeFarming.connect(addr1).swapETHForExactTokens(ethers.utils.parseEther(volumes[1]), pathEnT, addr1.address, bTimestamp * 2, { value: amountsIn[1] });
            balances[1] = Math.ceil(Number(ethers.utils.formatEther(await TFToken.balanceOf(addr1.address))));
            daily_records[1] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(addr1.address, currentDay))));

            amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volumes[2]), pathTnE);
            await tradeFarming.connect(addr2).swapETHForExactTokens(ethers.utils.parseEther(volumes[2]), pathEnT, addr2.address, bTimestamp * 2, { value: amountsIn[1] });
            balances[2] = Math.ceil(Number(ethers.utils.formatEther(await TFToken.balanceOf(addr2.address))));
            daily_records[2] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(addr2.address, currentDay))));

            daily_volumes[0] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.dailyVolumes(currentDay))));

            expectArgsEqual(balances[0] - initial_balances[0], daily_records[0], Number(volumes[0]));

            expect(daily_volumes[0]).to.be.equal(Number(volumes[0]) + Number(volumes[1]) + Number(volumes[2]));
            expect(Number(await tradeFarming.calcDay())).to.be.equal(0);
        });

        it("Day#1", async function () {
            let amountsIn;
            let volumes = ["500", "500", "2000"];
            let balances = [];
            let daily_records = [];
            let rewards = [];
            let previous_volumes;

            await increaseHours(25);
            currentDay = Number(await tradeFarming.calcDay());
            expect(Number(currentDay)).to.be.equal(1);


            total_volumes += Number(volumes[0]) + Number(volumes[1]) + Number(volumes[2]);

            amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volumes[0]), pathTnE);
            await tradeFarming.connect(owner).swapETHForExactTokens(ethers.utils.parseEther(volumes[0]), pathEnT, owner.address, bTimestamp * 2, { value: amountsIn[1] });
            balances[0] = Math.ceil(Number(ethers.utils.formatEther(await TFToken.balanceOf(owner.address))));
            daily_records[0] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(owner.address, currentDay))));

            amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volumes[1]), pathTnE);
            await tradeFarming.connect(addr1).swapETHForExactTokens(ethers.utils.parseEther(volumes[1]), pathEnT, addr1.address, bTimestamp * 2, { value: amountsIn[1] });
            balances[1] = Math.ceil(Number(ethers.utils.formatEther(await TFToken.balanceOf(addr1.address))));
            daily_records[1] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(addr1.address, currentDay))));

            amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volumes[2]), pathTnE);
            await tradeFarming.connect(addr2).swapETHForExactTokens(ethers.utils.parseEther(volumes[2]), pathEnT, addr2.address, bTimestamp * 2, { value: amountsIn[1] });
            balances[2] = Math.ceil(Number(ethers.utils.formatEther(await TFToken.balanceOf(addr2.address))));
            daily_records[2] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.volumeRecords(addr2.address, currentDay))));

            daily_volumes[1] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.dailyVolumes(currentDay))));

            expectArgsEqual(balances[0] - initial_balances[0], daily_records[0], Number(volumes[0]));
            expectArgsEqual(balances[1] - initial_balances[1], daily_records[1], Number(volumes[1]));
            expectArgsEqual(balances[2] - initial_balances[2], daily_records[2], Number(volumes[2]));

            expect(daily_volumes[1]).to.be.equal(Number(volumes[0]) + Number(volumes[1]) + Number(volumes[2]));            
            expect(Number(await tradeFarming.calcDay())).to.be.equal(1);

            previous_volumes = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.previousVolumes(1))));
            let tbe = ((((total_volumes - daily_volumes[1]) * currentDay) + (PREVIOUS_DAYS * Number(TOKEN_COUNT))) / 11)
            expect(previous_volumes).to.be.equal(tbe);

            rewards[0] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.connect(owner).calculateUserRewards())));
            rewards[1] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.connect(addr1).calculateUserRewards())));
            rewards[2] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.connect(addr2).calculateUserRewards())));

            expectArgsEqual(rewards[0], rewards[1], rewards[2]);
            
            await tradeFarming.connect(owner).claimAllRewards();

            new_reward_balances[0] = Math.ceil(Number(ethers.utils.formatEther(await rewardToken.balanceOf(owner.address))));

            expect(new_reward_balances[0]).to.be.equal(reward_balances[0] + rewards[0]);
            
            rewards[0] = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.connect(owner).calculateUserRewards())));
            expect(rewards[0]).to.be.equal(0);
        });
    });

});