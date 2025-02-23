# Morpho Optimizers

[![Morpho-Compound-Optimizer](https://github.com/morpho-dao/morpho-v1/actions/workflows/ci-foundry-compound.yml/badge.svg)](https://github.com/morpho-dao/morpho-v1/actions/workflows/ci-foundry-compound.yml)
[![Morpho-AaveV2-Optimizer](https://github.com/morpho-dao/morpho-v1/actions/workflows/ci-foundry-aave-v2.yml/badge.svg)](https://github.com/morpho-dao/morpho-v1/actions/workflows/ci-foundry-aave-v2.yml)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://i.imgur.com/uLq5V14.png">
  <img alt="" src="https://i.imgur.com/ZiL1Lr2.png">
</picture>

---

## What are Morpho Optimizers?

Morpho Optimizers improve the capital efficiency of positions on existing lending pools by seamlessly matching users peer-to-peer.

- Morpho's rates stay between the supply rate and the borrow rate of the pool, reducing the interest paid by the borrowers while increasing the interest earned by the suppliers. It means that you are getting boosted peer-to-peer rates or, in the worst-case scenario, the APY of the pool.
- Morpho also preserves the same experience, the same liquidity, and the same parameters (collateral factors, oracles, …) as the underlying pool.

TL;DR: Instead of borrowing or lending on your favorite pool like Compound or Aave, you would be better off using Morpho Optimizers.

---

## Contracts overview

Morpho Optimizers are designed at their core with a set of contracts delegating calls to implementation contracts (to overcome the contract size limit).

Here is a brief overview of the Morpho Optimizers' contracts interactions:

![image](https://user-images.githubusercontent.com/3147812/187162991-d9e94841-0f23-4f25-86d4-a495917b70e7.png)

The main user's entry points are exposed in the `Morpho` contract. It inherits from `MorphoGovernance`, which contains all the admin functions of the DAO, `MorphoUtils`, and `MorphoStorage`, where the protocol's storage is located. This contract delegates call to other contracts that have the same storage layout:

- `PositionsManager`: logic of basic supply, borrow, withdraw, repay, and liquidate functions. The Morpho-AaveV2 Optimizer is separated into two contracts, `EntryPositionsManager` and `ExitPositionsManager`. These contracts inherit from `MatchingEngine`, which contains the matching engine's internal functions.
- `InterestRatesManager`: logic of indexes computation.

It also interacts with `RewardsManager`, which manages the underlying pool's rewards, if any.

---

## Documentation

- [White Paper](https://whitepaper.morpho.org)
- [Yellow Paper](https://yellowpaper.morpho.org/)
- [Morpho Documentation](https://docs.morpho.org/concepts/morpho-optimizers)

---

## Audits

All audits are stored in the [audits](./audits/)' folder.

---

## Bug bounty

A bug bounty is open on Immunefi. The rewards and scope are defined [here](https://immunefi.com/bounty/morpho/).
You can email [security@morpho.org](mailto:security@morpho.org) if you find something worrying.

---

## Deployment Addresses

### Morpho-Compound Optimizer on Ethereum

- Morpho Proxy: [0x8888882f8f843896699869179fb6e4f7e3b58888](https://etherscan.io/address/0x8888882f8f843896699869179fb6e4f7e3b58888)
- Morpho Implementation: [0xe3d7a242614174ccf9f96bd479c42795d666fc81](https://etherscan.io/address/0xe3d7a242614174ccf9f96bd479c42795d666fc81)
- PositionsManager: [0x79a1b5888009bB4887E00EA27CF52551aAf2A004](https://etherscan.io/address/0x79a1b5888009bB4887E00EA27CF52551aAf2A004)
- InterestRatesManager: [0xD9B7209eD2936b5c06990A8356D155c3665d43Ab](https://etherscan.io/address/0xD9B7209eD2936b5c06990A8356D155c3665d43Ab)
- RewardsManager Proxy: [0x78681e63b6f3ad81ecd64aecc404d765b529c80d](https://etherscan.io/address/0x78681e63b6f3ad81ecd64aecc404d765b529c80d)
- RewardsManager Implementation: [0x581c3816589ad0de7f9c76bc242c97fe96c9f100](https://etherscan.io/address/0x581c3816589ad0de7f9c76bc242c97fe96c9f100)
- Lens Proxy: [0x930f1b46e1d081ec1524efd95752be3ece51ef67](https://etherscan.io/address/0x930f1b46e1d081ec1524efd95752be3ece51ef67)
- Lens Implementation: [0x834632a7c70ddd7badd3d21ba9d885a9da66b0de](https://etherscan.io/address/0x834632a7c70ddd7badd3d21ba9d885a9da66b0de)
- Lens Extension: [0xc5c3bB32c70d1d547023346BD1E32a6c5BC7FD1e](https://etherscan.io/address/0xc5c3bB32c70d1d547023346BD1E32a6c5BC7FD1e)
- CompRewardsLens: [0x9e977f745d5ae26c6d47ac5417ee112312873ba7](https://etherscan.io/address/0x9e977f745d5ae26c6d47ac5417ee112312873ba7)

### Morpho-AaveV2 Optimizer on Ethereum

- Morpho Proxy: [0x777777c9898d384f785ee44acfe945efdff5f3e0](https://etherscan.io/address/0x777777c9898d384f785ee44acfe945efdff5f3e0)
- Morpho Implementation: [0xFBc7693f114273739C74a3FF028C13769C49F2d0](https://etherscan.io/address/0xFBc7693f114273739C74a3FF028C13769C49F2d0)
- EntryPositionsManager: [0x029Ee1AF5BafC481f9E8FBeD5164253f1266B968](https://etherscan.io/address/0x029Ee1AF5BafC481f9E8FBeD5164253f1266B968)
- ExitPositionsManager: [0xfd9b1Ad429667D27cE666EA800f828B931A974D2](https://etherscan.io/address/0xfd9b1Ad429667D27cE666EA800f828B931A974D2)
- InterestRatesManager: [0x22a4ecf5195c87605ae6bad413ae79d5c4170ff1](https://etherscan.io/address/0x22a4ecf5195c87605ae6bad413ae79d5c4170ff1)
- Lens Proxy: [0x507fa343d0a90786d86c7cd885f5c49263a91ff4](https://etherscan.io/address/0x507fa343d0a90786d86c7cd885f5c49263a91ff4)
- Lens Implementation: [0x4bf26012b64312b462bf70f2e42d1be8881d0f84](https://etherscan.io/address/0x4bf26012b64312b462bf70f2e42d1be8881d0f84)

### Common Ethereum

- ProxyAdmin: [0x99917ca0426fbc677e84f873fb0b726bb4799cd8](https://etherscan.io/address/0x99917ca0426fbc677e84f873fb0b726bb4799cd8)

---

## Importing package

Using npm:

```bash
npm install @morpho-dao/morpho-v1
```

Using forge:

```bash
forge install @morpho-dao/morpho-v1@v2.0.0
```

Using git submodules:

```bash
git submodule add @morpho-dao/morpho-v1@v2.0.0 lib/morpho-v1
```

---

## Testing with [Foundry](https://github.com/foundry-rs/foundry) 🔨

Tests are run against a fork of real networks, allowing us to interact directly with Compound or Aave liquidity pools. Note that you need an RPC provider with access to Ethereum or Polygon.

For testing, make sure `yarn` and `foundry` are installed and install dependencies (node_modules, git submodules) with:

```bash
make install
```

Alternatively, if you only want to set up

Refer to the `env.example` for the required environment variable.

To run tests on different protocols, navigate a Unix terminal to the root folder of the project and run the command of your choice:

To run every test of a specific protocol (e.g. for the Morpho-Compound Optimizer):

```bash
make test PROTOCOL=compound
```

or to run only a specific set of tests of a specific protocol (e.g. for the Morpho-AaveV2 Optimizer):

```bash
make c-TestBorrow PROTOCOL=aave-v2
```

or to run an individual test of a specific protocol (e.g. for the Morpho-AaveV2 Optimizer):

```bash
make test-testBorrow1 PROTOCOL=aave-v2
```

For the other commands, check the [Makefile](./Makefile).

If you want to call a custom forge command and not have to edit the `Makefile`, you can _source_ the `export_env.sh` script by calling `. ./export_env.sh`.

:warning: The `export_env.sh` script exports environment variables in the current shell, meaning that subsequent calls to `make` or `forge` will use those variables. Variables defined in the `.env.local` file will still override those if you run `make` later. If you don't want to change variables in the current shell, you can always create a new shell in one of the following ways:

- use `( . ./export_env.sh && forge test )` if the command you want to run is `forge test`
- use `bash` and then `. ./export_env.sh` followed by your commands and then `exit` to return to the parent shell and clear the environment variables.

---

## Testing with Hardhat

Only tests for the [RewardsDistributor](./src/common/rewards-distribution/RewardsDistributor.sol) are run with Hardhat.

Just run:

```bash
yarn test
```

---

## Storage seatbelt

A CI pipeline [foundry-storage-check](https://github.com/Rubilmax/foundry-storage-diff) is running on every PR to check that the changes introduced are not modifying the storage layout of proxied smart contracts in an unsafe way.

---

## Deployment & Upgrades

### Network mode (default)

Run the Foundry deployment script with:

```bash
make script-Deploy PROTOCOL=compound NETWORK=goerli
```

### Local mode

First start a local EVM:

```bash
make anvil NETWORK=goerli
```

Then run the Foundry deployment script in a separate shell, using `SMODE=local`:

```bash
make script-Deploy PROTOCOL=compound NETWORK=goerli SMODE=local
```

---

## Questions & Feedback

For any questions or feedback, you can send an email to [merlin@morpho.org](mailto:merlin@morpho.org).

---

## Licensing

The code is under the GNU AFFERO GENERAL PUBLIC LICENSE v3.0, see [`LICENSE`](./LICENSE).
