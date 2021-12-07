import * as dotenv from 'dotenv';
dotenv.config({ path: './.env.local' });
import { utils, BigNumber, Signer, Contract } from 'ethers';
import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
const config = require(`@config/${process.env.NETWORK}-config.json`);
import { MAX_INT, removeDigitsBigNumber, bigNumberMin, to6Decimals, getTokens } from './utils/common-helpers';
import {
  WAD,
  // RAY,
  // underlyingToScaledBalance,
  // scaledBalanceToUnderlying,
  // underlyingToP2PUnit,
  // p2pUnitToUnderlying,
  // underlyingToAdUnit,
  // aDUnitToUnderlying,
  // computeNewMorphoExchangeRate,
} from './utils/aave-helpers';

// Commands to use those tests :
// terminal 1 : NETWORK=polygon-mainnet npx hardhat node
// terminal 2 : npx hardhat test test/aave-fuzzing.ts
// if the fuzzing finds a bug, the test script will stop
// and you can investigate the problem using the blockchain still
// running in terminal 2

describe('PositionsManagerForAave Contract', () => {
  const LIQUIDATION_CLOSE_FACTOR_PERCENT: BigNumber = BigNumber.from(5000);
  const SECOND_PER_YEAR: BigNumber = BigNumber.from(31536000);
  const PERCENT_BASE: BigNumber = BigNumber.from(10000);
  const AVERAGE_BLOCK_TIME: number = 2;

  // Tokens
  let aDaiToken: Contract;
  let daiToken: Contract;
  let usdcToken: Contract;
  // let wbtcToken: Contract;
  // let wmaticToken: Contract;
  let variableDebtDaiToken: Contract;

  // Contracts
  let positionsManagerForAave: Contract;
  let marketsManagerForAave: Contract;
  let fakeAavePositionsManager: Contract;
  let lendingPool: Contract;
  let lendingPoolAddressesProvider: Contract;
  let protocolDataProvider: Contract;
  let oracle: Contract;
  // let priceOracle: Contract;

  let underlyingThreshold: BigNumber;

  type Market = {
    token: Contract;
    config: any;
    aToken: Contract;
    loanToValue: number; // in percent
    liqThreshold: number; // in percent
    name: string;
    slotPosition: number;
  };

  let markets: Array<Market>;

  const initialize = async () => {
    ethers.provider = new ethers.providers.JsonRpcProvider('http://127.0.0.1:8545/');
    const owner = await ethers.getSigner('0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266');

    // Deploy DoubleLinkedList
    const DoubleLinkedList = await ethers.getContractFactory('contracts/aave/libraries/DoubleLinkedList.sol:DoubleLinkedList');
    const doubleLinkedList = await DoubleLinkedList.deploy();
    await doubleLinkedList.deployed();

    // Deploy MarketsManagerForAave
    const MarketsManagerForAave = await ethers.getContractFactory('MarketsManagerForAave');
    marketsManagerForAave = await MarketsManagerForAave.deploy(config.aave.lendingPoolAddressesProvider.address);
    await marketsManagerForAave.deployed();

    // Deploy PositionsManagerForAave
    const PositionsManagerForAave = await ethers.getContractFactory('PositionsManagerForAave');
    positionsManagerForAave = await PositionsManagerForAave.deploy(
      marketsManagerForAave.address,
      config.aave.lendingPoolAddressesProvider.address
    );
    fakeAavePositionsManager = await PositionsManagerForAave.deploy(
      marketsManagerForAave.address,
      config.aave.lendingPoolAddressesProvider.address
    );
    await positionsManagerForAave.deployed();
    await fakeAavePositionsManager.deployed();

    // Get contract dependencies
    const aTokenAbi = require(config.tokens.aToken.abi);
    const variableDebtTokenAbi = require(config.tokens.variableDebtToken.abi);
    aDaiToken = await ethers.getContractAt(aTokenAbi, config.tokens.aDai.address, owner);
    variableDebtDaiToken = await ethers.getContractAt(variableDebtTokenAbi, config.tokens.variableDebtDai.address, owner);
    lendingPool = await ethers.getContractAt(require(config.aave.lendingPool.abi), config.aave.lendingPool.address, owner);
    lendingPoolAddressesProvider = await ethers.getContractAt(
      require(config.aave.lendingPoolAddressesProvider.abi),
      config.aave.lendingPoolAddressesProvider.address,
      owner
    );
    protocolDataProvider = await ethers.getContractAt(
      require(config.aave.protocolDataProvider.abi),
      lendingPoolAddressesProvider.getAddress('0x1000000000000000000000000000000000000000000000000000000000000000'),
      owner
    );
    oracle = await ethers.getContractAt(require(config.aave.oracle.abi), lendingPoolAddressesProvider.getPriceOracle(), owner);

    // Mint some tokens
    daiToken = await ethers.getContractAt(require(config.tokens.dai.abi), config.tokens.dai.address, owner);
    usdcToken = await ethers.getContractAt(require(config.tokens.usdc.abi), config.tokens.usdc.address, owner);

    // daiToken = await getTokens(config.tokens.dai.whale, 'whale', signers, config.tokens.dai, utils.parseUnits('10000'));
    // usdcToken = await getTokens(config.tokens.usdc.whale, 'whale', signers, config.tokens.usdc, BigNumber.from(10).pow(10));
    // wbtcToken = await getTokens(config.tokens.wbtc.whale, 'whale', signers, config.tokens.wbtc, BigNumber.from(10).pow(8));
    // wmaticToken = await getTokens(config.tokens.wmatic.whale, 'whale', signers, config.tokens.wmatic, utils.parseUnits('100'));
    underlyingThreshold = WAD;

    // Create and list markets
    await marketsManagerForAave.connect(owner).setPositionsManager(positionsManagerForAave.address);
    await marketsManagerForAave.connect(owner).setLendingPool();
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aDai.address, WAD, MAX_INT);
    await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdc.address, to6Decimals(WAD), MAX_INT);
    // await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWbtc.address, BigNumber.from(10).pow(4), MAX_INT);
    // await marketsManagerForAave.connect(owner).createMarket(config.tokens.aUsdt.address, to6Decimals(WAD), MAX_INT);
    // await marketsManagerForAave.connect(owner).createMarket(config.tokens.aWmatic.address, WAD, MAX_INT);

    let daiMarket: Market = {
      token: daiToken,
      config: config.tokens.dai,
      aToken: aDaiToken,
      loanToValue: 75,
      liqThreshold: 80,
      name: 'dai',
      slotPosition: 0,
    };

    markets = [daiMarket];
  };

  before(initialize);

  const toBytes32 = (bn: BigNumber) => {
    return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
  };

  const setStorageAt = async (address: string, index: string, value: string) => {
    await ethers.provider.send('hardhat_setStorageAt', [address, index, value]);
    await ethers.provider.send('evm_mine', []); // Just mines to the next block
  };

  const tokenAmountToReadable = (bn: BigNumber, token: Contract) => {
    if (isA6DecimalsToken(token)) return bn.div(1e6).toString();
    else return bn.div(WAD).toString();
  };

  const giveTokensTo = async (token: string, receiver: string, amount: BigNumber, slotPosition: number) => {
    // Get storage slot index
    let index = ethers.utils.solidityKeccak256(
      ['uint256', 'uint256'],
      [receiver, slotPosition] // key, slot
    );
    await setStorageAt(token, index, toBytes32(amount));
  };

  const isA6DecimalsToken = (token: Contract) => {
    return token.address === config.tokens.usdc.address || token.address === config.tokens.usdt.address;
  };

  before(initialize);

  type Account = {
    address: string;
    signer: Signer;
    suppliedAmount: BigNumber;
    borrowedAmount: BigNumber;
  };

  describe('FUZZZZZZ EVERYTHING 🐙', () => {
    let accounts: Array<Account> = [];

    const generateAccount = async () => {
      let tokenDropSucceeded: boolean;
      let tempDropSucceeded: boolean;
      let ret: Account;
      do {
        tokenDropSucceeded = true;
        let retSign: Signer = ethers.Wallet.createRandom();
        retSign = retSign.connect(ethers.provider);
        let retAddr: string = await retSign.getAddress();
        await ethers.provider.send('hardhat_setBalance', [retAddr, utils.hexValue(utils.parseUnits('10000'))]);
        ret = { address: retAddr, signer: retSign, suppliedAmount: BigNumber.from(0), borrowedAmount: BigNumber.from(0) };
        for await (let market of markets) {
          tempDropSucceeded = await tryGiveTokens(ret, market);
          tokenDropSucceeded = tokenDropSucceeded && tempDropSucceeded;
        }
      } while (!tokenDropSucceeded); // as the token drop fails for some addresses, we loop until it works
      return ret;
    };

    const supply = async (account: Account, market: Market) => {
      // the amount to supply is chosen randomly between 1 and 1000 (1 minimum to avoid below threshold error)
      let amount: BigNumber = utils.parseUnits(Math.round(Math.random() * 1000).toString()).add(WAD);
      if (isA6DecimalsToken(market.token)) {
        amount = to6Decimals(amount);
      }
      await market.token.connect(account.signer).approve(positionsManagerForAave.address, amount);
      console.log('supplied ', tokenAmountToReadable(amount, market.token), market.name);
      await positionsManagerForAave.connect(account.signer).supply(market.aToken.address, amount);
      account.suppliedAmount = account.suppliedAmount.add(amount);
    };

    const tryGiveTokens = async (account: Account, market: Market) => {
      try {
        await giveTokensTo(market.token.address, account.address, utils.parseUnits('9999999'), market.slotPosition);
        return true;
      } catch {
        return false;
      }
    };

    const getARandomMarket = () => {
      return markets[Math.floor(Math.random() * markets.length)];
    };

    const getARandomAccount = () => {
      return accounts[Math.floor(Math.random() * accounts.length)];
    };

    const doWithAProbabiltyOfPercentage = async (percentage: number, callback: Function) => {
      if (Math.random() * 100 < percentage) {
        await callback();
      }
    };

    it('fouzzzz 🦑', async () => {
      const nbOfIterations: number = 100; // config

      console.log('initializing tests with 10 suppliers ...');

      for await (let i of [...Array(10).keys()]) {
        let tempAccount = await generateAccount();
        accounts.push(tempAccount);
        await supply(tempAccount, getARandomMarket());
      }

      console.log('now fuzzing 🦑');

      for await (let i of [...Array(nbOfIterations).keys()]) {
        console.log(`${i + 1}/${nbOfIterations}`);

        await doWithAProbabiltyOfPercentage(20, async () => {
          await generateAccount();
        });

        await doWithAProbabiltyOfPercentage(80, async () => {
          await supply(getARandomAccount(), getARandomMarket());
        });
      }

      //   for await (let market of markets) {
      //     for await (let i of [...Array(100).keys()]) {
      //       console.log(i);
      //       let supplier: Signer = ethers.Wallet.createRandom();
      //       supplier = supplier.connect(ethers.provider);
      //       supplierAddress = await supplier.getAddress();
      //       await ethers.provider.send('hardhat_setBalance', [supplierAddress, utils.hexValue(utils.parseUnits('10000'))]);

      //       // the amount to repay is chosen randomly between 1 and 1000 (1 minimum to avoid errors because below threshold)
      //       amount = utils.parseUnits(Math.round(Math.random() * 1000).toString()).add(WAD);
      //       if (isA6DecimalsToken(market.token)) {
      //         amount = to6Decimals(amount);
      //       }
      //       try {
      //         await giveTokensTo(market.token.address, supplierAddress, amount, market.slotPosition);
      //       } catch {
      //         tokenDropFailed = true;
      //         console.log('skipping one address');
      //       }
      //       if (!tokenDropFailed) {
      //         await market.token.connect(supplier).approve(positionsManagerForCompound.address, amount);
      //         console.log('supplied ', tokenAmountToReadable(amount, market.token), ' ', market.name);
      //         await positionsManagerForCompound.connect(supplier).supply(market.cToken.address, amount);
      //         suppliedAmount = amount;

      //         // we withdraw a random withdrawable amount with a probability of 1/2
      //         if (Math.random() > 0.5) {
      //           withrewAmount = amount.mul(BigNumber.from(Math.round(1000 * Math.random()))).div(1000);
      //           console.log('withdrew ', tokenAmountToReadable(withrewAmount, market.token), ' ', market.name);
      //           await positionsManagerForCompound.connect(supplier).withdraw(market.cToken.address, withrewAmount);
      //           suppliedAmount = suppliedAmount.sub(withrewAmount);
      //           console.log('remains ', tokenAmountToReadable(suppliedAmount, market.token), ' ', market.name);
      //         }
      //         // 80% chance
      //         if (Math.random() > 0.2) {
      //           borrowedMarket = markets[Math.floor(Math.random() * markets.length)]; // select a random market to borrow
      //           borrowedAmount = suppliedAmount
      //             .mul(market.collateralFactor)
      //             .div(100)
      //             .mul(Math.floor(1000 * Math.random()))
      //             .div(1000); // borrow random amount possible with what was supplied
      //           if (!isA6DecimalsToken(market.token) && isA6DecimalsToken(borrowedMarket.token)) {
      //             borrowedAmount = to6Decimals(borrowedAmount); // reduce to a 6 decimals equivalent amount
      //           }
      //           isAboveThreshold = isA6DecimalsToken(borrowedMarket.token) ? borrowedAmount.gt(to6Decimals(WAD)) : borrowedAmount.gt(WAD);
      //           if (isAboveThreshold) {
      //             console.log('borrowed ', tokenAmountToReadable(borrowedAmount, borrowedMarket.token), ' ', borrowedMarket.name);
      //             await positionsManagerForCompound.connect(supplier).borrow(borrowedMarket.cToken.address, borrowedAmount);
      //           }
      //         }
      //       }
      //       tokenDropFailed = false;
      //     }
      //   }
    });
  });
});
