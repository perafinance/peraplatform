const { expect } = require("chai");
const { ethers } = require("hardhat");
const TF = require("../artifacts/contracts/trade-farming/TradeFarming.sol/TradeFarming.json");
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
	const TOKEN_COUNT = "1000";
	const PREVIOUS_VOLUME = ethers.utils.parseUnits(TOKEN_COUNT, 18);
	const PREVIOUS_DAYS = 10;
	const TOTAL_DAYS = 5;

	let TFFactory, factory;
	let USDCoin, rewardToken;
	let TFToken;
	let tradeFarmingAddress, tradeFarming;
	let owner;
	let pathTnE, pathEnT;

	before(async function () {
		[owner] = await ethers.getSigners();

		USDCoin = await ethers.getContractFactory("USDCoin")
		rewardToken = await USDCoin.deploy();

		TFFactory = await ethers.getContractFactory("TradeFarmingFactory");
		factory = await TFFactory.deploy();

		await factory.createTnAPair(ROUTER_ADDRESS, TF_TOKEN_ADDRESS, rewardToken.address, PREVIOUS_VOLUME, PREVIOUS_DAYS, TOTAL_DAYS, 110, 90, owner.address);
		tradeFarmingAddress = await factory.getLastContract();
		tradeFarming = new ethers.Contract(tradeFarmingAddress, TF.abi, provider);

		pathTnE = [TF_TOKEN_ADDRESS, WETH_ADDRESS];
		pathEnT = [WETH_ADDRESS, TF_TOKEN_ADDRESS];

		TFToken = new ethers.Contract(TF_TOKEN_ADDRESS, tokenTF.abi, provider);

		await rewardToken.approve(tradeFarming.address, ethers.constants.MaxUint256);
		await tradeFarming.connect(owner).depositRewardTokens(PREVIOUS_VOLUME);
	});

	describe("Trade Farming", function () {
		let currentDay;
		let previousVolumes = [1000];
		let dailyVolumes = [];

		beforeEach(async function () {
			currentDay = Number(await tradeFarming.calcDay());
			bTimestamp = await getBlockTiemstamp();
		})

		it("Day #0", async function () {
			let amountsIn;
			let volume = "1000";
			amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volume), pathEnT);
			await tradeFarming.connect(owner).swapETHForExactTokens(ethers.utils.parseEther(volume), pathEnT, owner.address, bTimestamp * 2, { value: amountsIn[0] });
			dailyVolumes[currentDay] = Number(volume);
			expect(currentDay).to.be.equal(0);
		});

		it("Day #1", async function () {
			await increaseHours(25);
			currentDay = Number(await tradeFarming.calcDay());
			expect(currentDay).to.be.equal(1);

			let amountsIn;
			let volume = "2200";
			amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volume), pathEnT);
			await tradeFarming.connect(owner).swapETHForExactTokens(ethers.utils.parseEther(volume), pathEnT, owner.address, bTimestamp * 2, { value: amountsIn[0] });
			dailyVolumes[currentDay] = Number(volume);

			previousVolumes[1] = (previousVolumes[0] * (PREVIOUS_DAYS + currentDay - 1) + dailyVolumes[0]) / (PREVIOUS_DAYS + currentDay);
			let prev = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.previousVolumes(1))));
			expect(prev).to.be.equal(previousVolumes[1]);
		});

		it("Day #2", async function () {
			await increaseHours(24);
			currentDay = Number(await tradeFarming.calcDay());
			expect(currentDay).to.be.equal(2);

			let amountsIn;
			let volume = "6300";
			amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volume), pathEnT);
			await tradeFarming.connect(owner).swapETHForExactTokens(ethers.utils.parseEther(volume), pathEnT, owner.address, bTimestamp * 2, { value: amountsIn[0] });
			dailyVolumes[currentDay] = Number(volume);

			previousVolumes[2] = (previousVolumes[1] * (PREVIOUS_DAYS + currentDay - 1) + dailyVolumes[1]) / (PREVIOUS_DAYS + currentDay);
			let prev = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.previousVolumes(2))));
			expect(prev).to.be.equal(previousVolumes[2]);
		});

		it("Day #4", async function () {
			await increaseHours(48);
			currentDay = Number(await tradeFarming.calcDay());
			expect(currentDay).to.be.equal(4);
			let dailyReward = Number(ethers.utils.formatEther(await tradeFarming.connect(owner).dailyRewards(currentDay)));
			expect(dailyReward).to.be.equal(0);

			let amountsIn;
			let volume = "1500";
			amountsIn = await tradeFarming.getAmountsIn(ethers.utils.parseEther(volume), pathEnT);
			await tradeFarming.connect(owner).swapETHForExactTokens(ethers.utils.parseEther(volume), pathEnT, owner.address, bTimestamp * 2, { value: amountsIn[0] });
			dailyVolumes[currentDay] = Number(volume);

			dailyVolumes[3] = 0;
			expect(dailyVolumes[3]).to.be.equal(Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.dailyVolumes(3)))));

			previousVolumes[3] = (previousVolumes[2] * (PREVIOUS_DAYS + 3 - 1) + dailyVolumes[2]) / (PREVIOUS_DAYS + 3);
			let prev = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.previousVolumes(3))));
			expect(prev).to.be.equal(previousVolumes[3]);

			previousVolumes[4] = Math.ceil((previousVolumes[3] * (PREVIOUS_DAYS + currentDay - 1) + dailyVolumes[3]) / (PREVIOUS_DAYS + currentDay));
			prev = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.previousVolumes(4))));
			expect(prev).to.be.equal(previousVolumes[4]);
		});

		it("Day #5", async function () {
			await increaseHours(24);
			currentDay = Number(await tradeFarming.calcDay());
			expect(currentDay).to.be.equal(5);
			await tradeFarming.connect(owner).claimAllRewards();
			previousVolumes[5] = Math.ceil((previousVolumes[4] * (PREVIOUS_DAYS + currentDay - 1) + dailyVolumes[4]) / (PREVIOUS_DAYS + currentDay));
			prev = Math.ceil(Number(ethers.utils.formatEther(await tradeFarming.previousVolumes(5))));
			expect(prev + 1).to.be.equal(previousVolumes[5]); // +1 because of rounding
		});
	});
});