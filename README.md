# Quarry Draw Liquid Staking Contracts

The Liquid Staking of QuarryDraw is an adaptation of BenQI's liquid staking, it introduces a new ERC20: qdAVAX the QuarryDraw liquid staked AVAX. Quarry Draw adds the role of arbitrageurs within the logic. It's role is to provide liquidity for people that are wating to exit their position from the liquid staking. The earlier they provide liquidity the bigger the discount they'll recieve on redeemed qdAVAX.

This project uses a gas-optimized reference implementation for [EIP-2535 Diamonds](https://github.com/ethereum/EIPs/issues/2535). To learn more about this and other implementations go here: https://github.com/mudgen/diamond

This implementation uses Hardhat and Solidity 0.8.*

## Installation

1. Clone this repo:
```sh
git clone git@github.com:Puddi1/QD-LiquidStaking-Contracts.git
```

2. Install NPM packages:
```sh
cd QD-LiquidStaking-Contracts
npm i
```

## Compile

To compile the contracts in `./contract` run:

```sh
npx hardhat compile
```

Their artifacts will be placed in `./artifacts/contracts`

## Tests

To run test, which are stored in `./test` run:
```sh
npx hardhat test
```

## Deployment

Deployments scripts are handled in `./scripts`, to deploy:
```sh
npx hardhat run scripts/deploy.js
```