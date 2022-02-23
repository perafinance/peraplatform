# Pera Trade (Swap) Farming Protocol

![PERA](https://pera.finance/img/icons/logo.png)

### Written in [Solidity 0.8.11](https://docs.soliditylang.org/en/v0.8.11/) and uses [Hardhat](https://hardhat.org/)

<br/>

Pera Trade Farming Protocol enables Uniswap V2 fork DEXes to reward their users regarding to their trading volumes on specified token-ETH pair. Users can claim their rewards after the completion of the days. Configurated Trade Farming event contracts can be deployed with / without our ```TFFactory``` contract.

<br/>


Download the dependencies by
<br/>

```
npm install --save-dev hardhat
```

```
npm install @openzeppelin/contracts
```

```
npm install --save-dev @nomiclabs/hardhat-ethers ethers @nomiclabs/hardhat-waffle ethereum-waffle chai
```

Put your Alchemy API key for test with Ethereum mainnet fork.
Create ```keys/privatekey.json```  file in your project directory with your private key.

```
{
    "key" : "PRIVATE_KEY"
}
```

<br/>

## File Structure

```
contracts
├──── interfaces
│   ├── IPangolinRouter.sol
│   ├── ITradeFarming.sol
│   ├── ITradeFarming.sol
│   ├── ITradeFarmingAVAX.sol
│   └── IUniswapV2Router.sol
├──── trade-farming
│   ├── TradeFarming.sol
│   └── TradeFarmingAVAX.sol
├──── TFFactory.sol
└── TFFactory.sol

```