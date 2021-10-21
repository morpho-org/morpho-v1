require('dotenv').config({ path: '.env.local' });
const { utils, BigNumber } = require('ethers');
const { ethers } = require('hardhat');
const { expect } = require('chai');
const hre = require('hardhat');
const config = require('@config/polygon-config.json').polygon;

const {
  SCALE,
  underlyingToCToken,
  cTokenToUnderlying,
  underlyingToMUnit,
  mUnitToUnderlying,
  underlyingToCdUnit,
  cDUnitToUnderlying,
  removeDigitsBigNumber,
  bigNumberMin,
  to6Decimals,
  computeNewMorphoExchangeRate,
  getTokens,
} = require('./utils/helpers');


describe('MorphoPositionsManagerForCream Contract', () => {
  let cUsdcToken;
  let cDaiToken;
  let cUsdtToken;
  let cMkrToken;
  let daiToken;
  let usdtToken;
  let uniToken;
  let morphoPositionsManagerForCream;
  let pureLenderForCream;

  let signers;
  let owner;
  let supplier1;
  let supplier2;
  let supplier3;
  let borrower1;
  let borrower2;
  let borrower3;
  let liquidator;
  let addrs;
  let suppliers;
  let borrowers;

  let underlyingThreshold;

  beforeEach(async () => {
    // Users
    signers = await ethers.getSigners();
    [owner, supplier1, supplier2, supplier3, borrower1, borrower2, borrower3, liquidator, ...addrs] = signers;
    suppliers = [supplier1, supplier2, supplier3];
    borrowers = [borrower1, borrower2, borrower3];

    // Deploy contracts
    const RedBlackBinaryTree = await ethers.getContractFactory('RedBlackBinaryTree');
    const redBlackBinaryTree = await RedBlackBinaryTree.deploy();
    await redBlackBinaryTree.deployed();

    MorphoMarketsManagerForCompLike = await ethers.getContractFactory('MorphoMarketsManagerForCompLike');
    morphoMarketsManagerForCompLike = await MorphoMarketsManagerForCompLike.deploy();
    await morphoMarketsManagerForCompLike.deployed();

    MorphoPositionsManagerForCream = await ethers.getContractFactory('MorphoPositionsManagerForCream', {
      libraries: {
        RedBlackBinaryTree: redBlackBinaryTree.address,
      },
    });
    morphoPositionsManagerForCream = await MorphoPositionsManagerForCream.deploy(morphoMarketsManagerForCompLike.address, config.cream.comptroller.address);
    await morphoPositionsManagerForCream.deployed();

    PureLenderForCream = await ethers.getContractFactory('PureLenderForCream');
    pureLenderForCream = await PureLenderForCream.deploy(morphoPositionsManagerForCream.address);
    await pureLenderForCream.deployed();

    // Get contract dependencies
    const cTokenAbi = require(config.tokens.cToken.abi);
    cUsdcToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdc.address, owner);
    cDaiToken = await ethers.getContractAt(cTokenAbi, config.tokens.cDai.address, owner);
    cUsdtToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUsdt.address, owner);
    cUniToken = await ethers.getContractAt(cTokenAbi, config.tokens.cUni.address, owner);
    cMkrToken = await ethers.getContractAt(cTokenAbi, config.tokens.cMkr.address, owner); // This is in fact crLINK tokens (no crMKR on Polygon)

    comptroller = await ethers.getContractAt(require(config.cream.comptroller.abi), config.cream.comptroller.address, owner);
    compoundOracle = await ethers.getContractAt(require(config.cream.oracle.abi), comptroller.oracle(), owner);

    // Mint some ERC20
    daiToken = await getTokens('0x27f8d03b3a2196956ed754badc28d73be8830a6e', 'whale', signers, config.tokens.dai, utils.parseUnits('10000'));
    usdcToken = await getTokens('0x1a13f4ca1d028320a707d99520abfefca3998b7f', 'whale', signers, config.tokens.usdc, BigNumber.from(10).pow(10));
    usdtToken = await getTokens('0x44aaa9ebafb4557605de574d5e968589dc3a84d1', 'whale', signers, config.tokens.usdt, BigNumber.from(10).pow(10));
    uniToken = await getTokens('0xf7135272a5584eb116f5a77425118a8b4a2ddfdb', 'whale', signers, config.tokens.uni, utils.parseUnits('100'));

    underlyingThreshold = utils.parseUnits('1');

    // Create and list markets
    await morphoMarketsManagerForCompLike.connect(owner).setPositionsManagerForCompLike(morphoPositionsManagerForCream.address);
    await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cDai.address);
    await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cUsdc.address);
    await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cUni.address);
    await morphoMarketsManagerForCompLike.connect(owner).createMarket(config.tokens.cUsdt.address);
    await morphoMarketsManagerForCompLike.connect(owner).updateThreshold(config.tokens.cUsdc.address, BigNumber.from(1).pow(6));
    await morphoMarketsManagerForCompLike.connect(owner).updateThreshold(config.tokens.cUsdt.address, BigNumber.from(1).pow(6));
  });

  describe('Deployment', () => {
    it('Should deploy the contract with the right values', async () => {
      expect(await pureLenderForCream.marketsManager()).to.equal(morphoMarketsManagerForCompLike.address);
      expect(await pureLenderForCream.positionsManager()).to.equal(morphoPositionsManagerForCream.address);
    });
  });

  describe('Depositors', () => {

    it.('users deposit', async () => {
      const amount1 = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(supplier1).approve(pureLenderForCream.address, amount1);
      await pureLenderForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount1);
      console.log('Supply 1 done');

      const amount2 = to6Decimals(utils.parseUnits('200'));
      await usdcToken.connect(supplier2).approve(pureLenderForCream.address, amount2);
      await pureLenderForCream.connect(supplier2).supply(config.tokens.cUsdc.address, amount2);
      console.log('Supply 2 done');

      const shares1 = await pureLenderForCream.shares(config.tokens.cUsdc.address, supplier1.address);
      console.log('Supplier 1 shares', shares1.toString());
      const shares2 = await pureLenderForCream.shares(config.tokens.cUsdc.address, supplier2.address)
      console.log('Supplier 2 shares', shares2.toString());

      await mineBlocks(1000);
      await pureLenderForCream.connect(supplier2).withdraw(config.tokens.cUsdc.address, shares2);
      console.log('Supplier 1 balance', await usdcToken.balanceOf(supplier1.address));
      console.log('Supplier 2 shares', await pureLenderForCream.shares(config.tokens.cUsdc.address, supplier2.address));
      console.log('Pure lender balance on PositionsManager', await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, pureLenderForCream.address));
    });

    it.only('Multiple Deposits Scenario 1', async () => {
      // Alice supplies 50 tokens
      const amount = to6Decimals(utils.parseUnits('50'));
      await usdcToken.connect(supplier1).approve(pureLenderForCream.address, amount);
      await pureLenderForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount);

      mineBlocks(10);

      // Alice supplies again 50 tokens
      await usdcToken.connect(supplier1).approve(pureLenderForCream.address, amount);
      await pureLenderForCream.connect(supplier1).supply(config.tokens.cUsdc.address, amount);

      mineBlocks(10);

      // Bob supplies 50 tokens
      await usdcToken.connect(supplier2).approve(pureLenderForCream.address, amount);
      await pureLenderForCream.connect(supplier2).supply(config.tokens.cUsdc.address, amount);

      await mineBlocks(1000);

      await pureLenderForCream.connect(supplier2).withdraw(config.tokens.cUsdc.address, amount);

      console.log('Supplier 1 balance', await usdcToken.balanceOf(supplier1.address));
      console.log('Supplier 2 balance', await usdcToken.balanceOf(supplier2.address));
      console.log('Karl balance on PositionsManager', await morphoPositionsManagerForCream.supplyBalanceInOf(config.tokens.cUsdc.address, pureLenderForCream.address));
    });

  });

  async function mineBlocks(blockNumber) {
    while (blockNumber > 0) {
      blockNumber--;
      await hre.network.provider.send('evm_mine', []);
    }
  }

});
