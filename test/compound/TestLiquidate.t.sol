// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestLiquidate is TestSetup {
    using SafeTransferLib for ERC20;
    using CompoundMath for uint256;

    // A user liquidates a borrower that has enough collateral to cover for his debt, the transaction reverts.
    function testShouldNotBePossibleToLiquidateUserAboveWater() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, address(morpho), to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, amount);

        // Liquidate
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(morpho), toRepay);

        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedLiquidate()"));
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);
    }

    function testShouldNotLiquidateZero() public {
        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        borrower2.liquidate(cDai, cUsdc, address(borrower1), 0);
    }

    function testLiquidateWhenMarketDeprecated() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = to6Decimals(3 * amount);

        borrower1.approve(usdc, address(morpho), collateral);
        borrower1.supply(cUsdc, collateral);
        borrower1.borrow(cDai, amount);

        morpho.setIsBorrowPaused(cDai, true);
        morpho.setIsDeprecated(cDai, true);

        moveOneBlockForwardBorrowRepay();

        (, uint256 supplyOnPoolBefore) = morpho.supplyBalanceInOf(cUsdc, address(borrower1));

        // Liquidate
        uint256 toRepay = amount; // Full liquidation.
        User liquidator = borrower3;
        liquidator.approve(dai, address(morpho), toRepay);
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);

        (, uint256 supplyOnPoolAfter) = morpho.supplyBalanceInOf(cUsdc, address(borrower1));
        (, uint256 borrowOnPoolAfter) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 collateralPrice = oracle.getUnderlyingPrice(cUsdc);
        uint256 borrowedPrice = oracle.getUnderlyingPrice(cDai);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedSupplyOnPoolAfter = supplyOnPoolBefore -
            amountToSeize.div(ICToken(cUsdc).exchangeRateCurrent());

        assertApproxEqAbs(supplyOnPoolAfter, expectedSupplyOnPoolAfter, 2);
        assertApproxEqAbs(borrowOnPoolAfter, 0, 1e15);
    }

    // A user liquidates a borrower that has not enough collateral to cover for his debt.
    function testShouldLiquidateUser() public {
        uint256 collateral = 100_000 ether;

        borrower1.approve(usdc, address(morpho), to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        (, uint256 amount) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cDai);
        borrower1.borrow(cDai, amount);

        (, uint256 collateralOnPool) = morpho.supplyBalanceInOf(cUsdc, address(borrower1));

        moveOneBlockForwardBorrowRepay();

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(usdc, (oracle.getUnderlyingPrice(cUsdc) * 98) / 100);

        // Liquidate.
        uint256 toRepay = amount / 2;
        User liquidator = borrower3;
        liquidator.approve(dai, address(morpho), toRepay);
        liquidator.liquidate(cDai, cUsdc, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        uint256 expectedBorrowBalanceOnPool = toRepay.div(ICToken(cDai).borrowIndex());
        testEqualityLarge(onPoolBorrower, expectedBorrowBalanceOnPool, "borrower borrow on pool");
        assertEq(inP2PBorrower, 0, "borrower borrow in peer-to-peer");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(cUsdc, address(borrower1));

        uint256 collateralPrice = customOracle.getUnderlyingPrice(cUsdc);
        uint256 borrowedPrice = customOracle.getUnderlyingPrice(cDai);

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(borrowedPrice)
        .div(collateralPrice);

        uint256 expectedOnPool = collateralOnPool -
            amountToSeize.div(ICToken(cUsdc).exchangeRateCurrent());

        testEquality(onPoolBorrower, expectedOnPool, "borrower supply on pool");
        assertEq(inP2PBorrower, 0, "borrower supply in peer-to-peer");
    }

    function testShouldLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(cUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(cDai, collateral);

        (, uint256 borrowerDebt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdc);
        (, uint256 supplierDebt) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cDai);

        supplier1.borrow(cDai, supplierDebt);
        borrower1.borrow(cUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = morpho.supplyBalanceInOf(cDai, address(borrower1));

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getUnderlyingPrice(cDai) * 94) / 100);

        moveOneBlockForwardBorrowRepay();

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 2) - 1; // -1 because of rounding error related to compound's approximation
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(cUsdc, cDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceInP2P = onPoolUsdc.mul(ICToken(cUsdc).borrowIndex()) +
            inP2PUsdc.mul(morpho.p2pBorrowIndex(cUsdc)) -
            (borrowerDebt / 2);

        assertEq(onPoolBorrower, 0, "borrower borrow on pool");
        testEquality(
            inP2PBorrower.mul(morpho.p2pBorrowIndex(cUsdc)),
            expectedBorrowBalanceInP2P,
            "borrower borrow in peer-to-peer"
        );

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(cDai, address(borrower1));

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(customOracle.getUnderlyingPrice(cUsdc))
        .div(customOracle.getUnderlyingPrice(cDai));

        testEquality(
            onPoolBorrower,
            onPoolDai - amountToSeize.div(ICToken(cDai).exchangeRateCurrent()),
            "borrower supply on pool"
        );
        testEquality(inP2PBorrower, inP2PDai, "borrower supply in peer-to-peer");
    }

    function testShouldPartiallyLiquidateWhileInP2PAndPool() public {
        uint256 collateral = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(collateral) / 2);
        supplier1.supply(cUsdc, to6Decimals(collateral) / 2);

        borrower1.approve(dai, collateral);
        borrower1.supply(cDai, collateral);

        (, uint256 borrowerDebt) = lens.getUserMaxCapacitiesForAsset(address(borrower1), cUsdc);
        (, uint256 supplierDebt) = lens.getUserMaxCapacitiesForAsset(address(supplier1), cDai);

        supplier1.borrow(cDai, supplierDebt);
        borrower1.borrow(cUsdc, borrowerDebt);

        (uint256 inP2PUsdc, uint256 onPoolUsdc) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        (uint256 inP2PDai, uint256 onPoolDai) = morpho.supplyBalanceInOf(cDai, address(borrower1));

        // Change Oracle.
        SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
        customOracle.setDirectPrice(dai, (oracle.getUnderlyingPrice(cDai) * 94) / 100);

        moveOneBlockForwardBorrowRepay();

        // Liquidate.
        uint256 toRepay = (borrowerDebt / 4);
        User liquidator = borrower3;
        liquidator.approve(usdc, toRepay);
        liquidator.liquidate(cUsdc, cDai, address(borrower1), toRepay);

        // Check borrower1 borrow balance.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cUsdc,
            address(borrower1)
        );

        uint256 expectedBorrowBalanceOnPool = onPoolUsdc.mul(ICToken(cUsdc).borrowIndex()) -
            toRepay;

        testEqualityLarge(
            onPoolBorrower.mul(ICToken(cUsdc).borrowIndex()),
            expectedBorrowBalanceOnPool,
            "borrower borrow on pool"
        );
        testEquality(inP2PBorrower, inP2PUsdc, "borrower borrow in peer-to-peer");

        // Check borrower1 supply balance.
        (inP2PBorrower, onPoolBorrower) = morpho.supplyBalanceInOf(cDai, address(borrower1));

        uint256 amountToSeize = toRepay
        .mul(comptroller.liquidationIncentiveMantissa())
        .mul(customOracle.getUnderlyingPrice(cUsdc))
        .div(customOracle.getUnderlyingPrice(cDai));

        testEquality(
            onPoolBorrower,
            onPoolDai - amountToSeize.div(ICToken(cDai).exchangeRateCurrent()),
            "borrower supply on pool"
        );
        testEquality(inP2PBorrower, inP2PDai, "borrower supply in peer-to-peer");
    }

    function testLiquidateZero() public {
        vm.expectRevert();
        morpho.liquidate(cDai, cDai, cDai, 0);
    }

    struct StackP2PVars {
        uint256 daiP2PSupplyIndexBefore;
        uint256 daiP2PBorrowIndexBefore;
        uint256 usdcP2PSupplyIndexBefore;
        uint256 usdcP2PBorrowIndexBefore;
        uint256 batP2PSupplyIndexBefore;
        uint256 batP2PBorrowIndexBefore;
        uint256 usdtP2PSupplyIndexBefore;
        uint256 usdtP2PBorrowIndexBefore;
    }

    struct StackPoolVars {
        uint256 daiPoolSupplyIndexBefore;
        uint256 daiPoolBorrowIndexBefore;
        uint256 usdcPoolSupplyIndexBefore;
        uint256 usdcPoolBorrowIndexBefore;
        uint256 batPoolSupplyIndexBefore;
        uint256 batPoolBorrowIndexBefore;
        uint256 usdtPoolSupplyIndexBefore;
        uint256 usdtPoolBorrowIndexBefore;
    }

    function testLiquidateUpdateIndexesSameAsCompound() public {
        uint256 collateral = 1 ether;
        uint256 borrow = collateral / 2;
        uint256 formerPriceDai;
        uint256 formerPriceUsdc;

        {
            supplier1.approve(dai, type(uint256).max);
            supplier1.approve(usdc, type(uint256).max);
            supplier1.approve(usdt, type(uint256).max);

            supplier1.supply(cDai, collateral);
            supplier1.supply(cUsdc, to6Decimals(collateral));

            supplier1.borrow(cBat, borrow);
            supplier1.borrow(cUsdt, to6Decimals(borrow));

            supplier2.approve(wEth, type(uint256).max);
            supplier2.supply(cEth, collateral);

            StackP2PVars memory vars;

            vars.daiP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cDai);
            vars.daiP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cDai);
            vars.usdcP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cUsdc);
            vars.usdcP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cUsdc);
            vars.batP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cBat);
            vars.batP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cBat);
            vars.usdtP2PSupplyIndexBefore = morpho.p2pSupplyIndex(cUsdt);
            vars.usdtP2PBorrowIndexBefore = morpho.p2pBorrowIndex(cUsdt);

            hevm.roll(block.number + 1);

            // Change Oracle.
            SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
            formerPriceDai = oracle.getUnderlyingPrice(cDai);
            formerPriceUsdc = oracle.getUnderlyingPrice(cUsdc);
            customOracle.setDirectPrice(dai, (formerPriceDai * 10) / 100);
            customOracle.setDirectPrice(usdc, (formerPriceUsdc * 10) / 100);

            // Liquidate.
            uint256 toRepay = (to6Decimals(borrow) * 1) / 100;
            User liquidator = borrower3;
            liquidator.approve(usdt, toRepay);
            liquidator.liquidate(cUsdt, cDai, address(supplier1), toRepay);

            // Reset former price on oracle.
            customOracle.setDirectPrice(dai, formerPriceDai);
            customOracle.setDirectPrice(usdc, formerPriceUsdc);

            uint256 daiP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cDai);
            uint256 daiP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cDai);
            uint256 usdcP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cUsdc);
            uint256 usdcP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cUsdc);
            uint256 batP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cBat);
            uint256 batP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cBat);
            uint256 usdtP2PSupplyIndexAfter = morpho.p2pSupplyIndex(cUsdt);
            uint256 usdtP2PBorrowIndexAfter = morpho.p2pBorrowIndex(cUsdt);

            assertGt(daiP2PBorrowIndexAfter, vars.daiP2PSupplyIndexBefore);
            assertGt(daiP2PSupplyIndexAfter, vars.daiP2PBorrowIndexBefore);
            assertEq(usdcP2PSupplyIndexAfter, vars.usdcP2PSupplyIndexBefore);
            assertEq(usdcP2PBorrowIndexAfter, vars.usdcP2PBorrowIndexBefore);
            assertEq(batP2PSupplyIndexAfter, vars.batP2PSupplyIndexBefore);
            assertEq(batP2PBorrowIndexAfter, vars.batP2PBorrowIndexBefore);
            assertGt(usdtP2PSupplyIndexAfter, vars.usdtP2PSupplyIndexBefore);
            assertGt(usdtP2PBorrowIndexAfter, vars.usdtP2PBorrowIndexBefore);
        }

        {
            supplier1.compoundSupply(cDai, collateral);
            supplier1.compoundSupply(cUsdc, to6Decimals(collateral));

            supplier1.compoundBorrow(cBat, borrow);
            supplier1.compoundBorrow(cUsdt, to6Decimals(borrow));

            StackPoolVars memory vars;

            vars.daiPoolSupplyIndexBefore = ICToken(cDai).exchangeRateStored();
            vars.daiPoolBorrowIndexBefore = ICToken(cDai).borrowIndex();
            vars.usdcPoolSupplyIndexBefore = ICToken(cUsdc).exchangeRateStored();
            vars.usdcPoolBorrowIndexBefore = ICToken(cUsdc).borrowIndex();
            vars.batPoolSupplyIndexBefore = ICToken(cBat).exchangeRateStored();
            vars.batPoolBorrowIndexBefore = ICToken(cBat).borrowIndex();
            vars.usdtPoolSupplyIndexBefore = ICToken(cUsdt).exchangeRateStored();
            vars.usdtPoolBorrowIndexBefore = ICToken(cUsdt).borrowIndex();

            hevm.roll(block.number + 1);

            // Change Oracle.
            SimplePriceOracle customOracle = createAndSetCustomPriceOracle();
            customOracle.setDirectPrice(dai, (formerPriceDai * 10) / 100);
            customOracle.setDirectPrice(usdc, (formerPriceUsdc * 10) / 100);

            // Liquidate.
            uint256 toRepay = (to6Decimals(borrow) * 1) / 100;
            hevm.prank(address(borrower3));
            ERC20(usdt).safeApprove(cUsdt, type(uint256).max);
            hevm.prank(address(borrower3));
            ICToken(cUsdt).liquidateBorrow(address(supplier1), toRepay, cDai);

            // Reset former price on oracle.
            customOracle.setDirectPrice(dai, formerPriceDai);
            customOracle.setDirectPrice(usdc, formerPriceUsdc);

            uint256 daiPoolSupplyIndexAfter = ICToken(cDai).exchangeRateStored();
            uint256 daiPoolBorrowIndexAfter = ICToken(cDai).borrowIndex();
            uint256 usdcPoolSupplyIndexAfter = ICToken(cUsdc).exchangeRateStored();
            uint256 usdcPoolBorrowIndexAfter = ICToken(cUsdc).borrowIndex();
            uint256 batPoolSupplyIndexAfter = ICToken(cBat).exchangeRateStored();
            uint256 batPoolBorrowIndexAfter = ICToken(cBat).borrowIndex();
            uint256 usdtPoolSupplyIndexAfter = ICToken(cUsdt).exchangeRateStored();
            uint256 usdtPoolBorrowIndexAfter = ICToken(cUsdt).borrowIndex();

            assertGt(daiPoolSupplyIndexAfter, vars.daiPoolSupplyIndexBefore);
            assertGt(daiPoolBorrowIndexAfter, vars.daiPoolBorrowIndexBefore);
            assertEq(usdcPoolSupplyIndexAfter, vars.usdcPoolSupplyIndexBefore);
            assertEq(usdcPoolBorrowIndexAfter, vars.usdcPoolBorrowIndexBefore);
            assertEq(batPoolSupplyIndexAfter, vars.batPoolSupplyIndexBefore);
            assertEq(batPoolBorrowIndexAfter, vars.batPoolBorrowIndexBefore);
            assertGt(usdtPoolSupplyIndexAfter, vars.usdtPoolSupplyIndexBefore);
            assertGt(usdtPoolBorrowIndexAfter, vars.usdtPoolBorrowIndexBefore);
        }
    }

    function testCannotLiquidateMoreThanCloseFactor() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setUnderlyingPrice(cUsdc, oracle.getUnderlyingPrice(cDai) * 1e12);

        borrower1.approve(usdc, type(uint256).max);
        borrower1.supply(cUsdc, to6Decimals(amount * 2));
        borrower1.borrow(cDai, amount);

        oracle.setUnderlyingPrice(cUsdc, oracle.getUnderlyingPrice(cUsdc) / 2);
        vm.roll(block.number + 1);

        borrower2.approve(dai, amount);
        hevm.prank(address(borrower2));
        hevm.expectRevert(abi.encodeWithSignature("AmountAboveWhatAllowedToRepay()"));
        morpho.liquidate(cDai, cUsdc, address(borrower1), (amount * 3) / 4);
    }

    function testCannotBorrowLiquidateInSameBlock() public {
        uint256 amount = 10_000 ether;

        SimplePriceOracle oracle = createAndSetCustomPriceOracle();
        oracle.setUnderlyingPrice(cUsdc, oracle.getUnderlyingPrice(cDai) * 1e12);

        borrower1.approve(usdc, type(uint256).max);
        borrower1.supply(cUsdc, to6Decimals(amount * 2));
        borrower1.borrow(cDai, amount);

        oracle.setUnderlyingPrice(cUsdc, oracle.getUnderlyingPrice(cUsdc) / 2);

        borrower2.approve(dai, amount);
        hevm.prank(address(borrower2));
        hevm.expectRevert(abi.encodeWithSignature("SameBlockBorrowRepay()"));
        morpho.liquidate(cDai, cUsdc, address(borrower1), amount / 3);
    }
}
