// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestGovernance is TestSetup {
    using CompoundMath for uint256;

    function testShouldDeployContractWithTheRightValues() public {
        assertEq(
            morpho.p2pSupplyIndex(cDai),
            2 * 10**(16 + ERC20(ICToken(cDai).underlying()).decimals() - 8)
        );
        assertEq(
            morpho.p2pBorrowIndex(cDai),
            2 * 10**(16 + ERC20(ICToken(cDai).underlying()).decimals() - 8)
        );
    }

    function testShouldRevertWhenCreatingMarketWithAnImproperMarket() public {
        Types.MarketParameters memory marketParams = Types.MarketParameters(3_333, 0);

        hevm.expectRevert(abi.encodeWithSignature("MarketCreationFailedOnCompound(uint256)", 9));
        morpho.createMarket(address(supplier1), marketParams);
    }

    function testOnlyOwnerCanCreateMarkets() public {
        Types.MarketParameters memory marketParams = Types.MarketParameters(3_333, 0);

        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.createMarket(pools[i], marketParams);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.createMarket(pools[i], marketParams);
        }

        morpho.createMarket(cAave, marketParams);
    }

    function testShouldCreateMarketWithRightParams() public {
        Types.MarketParameters memory rightParams = Types.MarketParameters(1_000, 3_333);
        Types.MarketParameters memory wrongParams1 = Types.MarketParameters(10_001, 0);
        Types.MarketParameters memory wrongParams2 = Types.MarketParameters(0, 10_001);

        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(cAave, wrongParams1);
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(cAave, wrongParams2);

        morpho.createMarket(cAave, rightParams);
        (uint16 reserveFactor, uint256 p2pIndexCursor) = morpho.marketParameters(cAave);
        assertEq(reserveFactor, 1_000);
        assertEq(p2pIndexCursor, 3_333);
    }

    function testOnlyOwnerCanSetReserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setReserveFactor(cDai, 1111);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setReserveFactor(cDai, 1111);
        }

        morpho.setReserveFactor(cDai, 1111);
    }

    function testReserveFactorShouldBeUpdatedWithRightValue() public {
        morpho.setReserveFactor(cDai, 1111);
        (uint16 reserveFactor, ) = morpho.marketParameters(cDai);
        assertEq(reserveFactor, 1111);
    }

    function testShouldCreateMarketWithTheRightValues() public {
        ICToken cToken = ICToken(cAave);
        Types.MarketParameters memory marketParams = Types.MarketParameters(3_333, 0);
        morpho.createMarket(cAave, marketParams);

        (bool isCreated, , ) = morpho.marketStatus(cAave);

        assertTrue(isCreated);
        assertEq(
            morpho.p2pSupplyIndex(cAave),
            2 * 10**(16 + ERC20(cToken.underlying()).decimals() - 8)
        );
        assertEq(
            morpho.p2pBorrowIndex(cAave),
            2 * 10**(16 + ERC20(cToken.underlying()).decimals() - 8)
        );
    }

    function testShouldSetMaxGasWithRightValues() public {
        Types.MaxGasForMatching memory newMaxGas = Types.MaxGasForMatching({
            supply: 1,
            borrow: 1,
            withdraw: 1,
            repay: 1
        });

        morpho.setDefaultMaxGasForMatching(newMaxGas);
        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = morpho
        .defaultMaxGasForMatching();
        assertEq(supply, newMaxGas.supply);
        assertEq(borrow, newMaxGas.borrow);
        assertEq(withdraw, newMaxGas.withdraw);
        assertEq(repay, newMaxGas.repay);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setDefaultMaxGasForMatching(newMaxGas);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setDefaultMaxGasForMatching(newMaxGas);
    }

    function testOnlyOwnerCanSetMaxSortedUsers() public {
        uint256 newMaxSortedUsers = 30;

        morpho.setMaxSortedUsers(newMaxSortedUsers);
        assertEq(morpho.maxSortedUsers(), newMaxSortedUsers);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setMaxSortedUsers(newMaxSortedUsers);

        hevm.expectRevert("Ownable: caller is not the owner");
        borrower1.setMaxSortedUsers(newMaxSortedUsers);
    }

    function testOnlyOwnerShouldFlipMarketStrategy() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsP2PDisabled(cDai, true);

        hevm.expectRevert("Ownable: caller is not the owner");
        supplier2.setIsP2PDisabled(cDai, true);

        morpho.setIsP2PDisabled(cDai, true);
        assertTrue(morpho.p2pDisabled(cDai));
    }

    function testOnlyOwnerShouldSetPositionsManager() public {
        IPositionsManager positionsManagerV2 = new PositionsManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setPositionsManager(positionsManagerV2);

        morpho.setPositionsManager(positionsManagerV2);
        assertEq(address(morpho.positionsManager()), address(positionsManagerV2));
    }

    function testOnlyOwnerShouldSetRewardsManager() public {
        IRewardsManager rewardsManagerV2 = new RewardsManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setRewardsManager(rewardsManagerV2);

        morpho.setRewardsManager(rewardsManagerV2);
        assertEq(address(morpho.rewardsManager()), address(rewardsManagerV2));
    }

    function testOnlyOwnerShouldSetInterestRatesManager() public {
        IInterestRatesManager interestRatesV2 = new InterestRatesManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setInterestRatesManager(interestRatesV2);

        morpho.setInterestRatesManager(interestRatesV2);
        assertEq(address(morpho.interestRatesManager()), address(interestRatesV2));
    }

    function testOnlyOwnerShouldSetDustThreshold() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setDustThreshold(1e8);

        morpho.setDustThreshold(1e8);
        assertEq(morpho.dustThreshold(), 1e8);
    }

    function testOnlyOwnerShouldSetTreasuryVault() public {
        address treasuryVaultV2 = address(2);

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setTreasuryVault(treasuryVaultV2);

        morpho.setTreasuryVault(treasuryVaultV2);
        assertEq(address(morpho.treasuryVault()), treasuryVaultV2);
    }

    function testOnlyOwnerCanSetIsClaimRewardsPaused() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsClaimRewardsPaused(true);

        morpho.setIsClaimRewardsPaused(true);
        assertTrue(morpho.isClaimRewardsPaused());
    }

    function testSetP2PIndexCursor() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setP2PIndexCursor(cDai, 5000);

        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.setP2PIndexCursor(cDai, 10001);

        morpho.setP2PIndexCursor(cDai, 6969);
        (, uint16 p2pIndexCursor) = morpho.marketParameters(cDai);
        assertEq(p2pIndexCursor, 6969);
    }

    function testOnlyOwnerShouldSetDeprecatedMarket() public {
        morpho.setIsBorrowPaused(cDai, true);

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsDeprecated(cDai, true);

        hevm.prank(address(supplier2));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsDeprecated(cDai, true);

        morpho.setIsDeprecated(cDai, true);
        (, , , , , , bool isDeprecated) = morpho.marketPauseStatus(cDai);
        assertTrue(isDeprecated);

        morpho.setIsDeprecated(cDai, false);
        (, , , , , , isDeprecated) = morpho.marketPauseStatus(cDai);
        assertFalse(isDeprecated);
    }

    function testOnlyOwnerShouldDisableSupply() public {
        (bool isSupplyPaused, , , , , , ) = morpho.marketPauseStatus(cDai);
        assertFalse(isSupplyPaused);

        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsSupplyPaused(cDai, true);

        morpho.setIsSupplyPaused(cDai, true);
        (isSupplyPaused, , , , , , ) = morpho.marketPauseStatus(cDai);
        assertTrue(isSupplyPaused);
    }

    function testOnlyOwnerShouldDisableBorrow() public {
        (, bool isBorrowPaused, , , , , ) = morpho.marketPauseStatus(cDai);
        assertFalse(isBorrowPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsBorrowPaused(cDai, true);

        morpho.setIsBorrowPaused(cDai, true);
        (, isBorrowPaused, , , , , ) = morpho.marketPauseStatus(cDai);
        assertTrue(isBorrowPaused);
    }

    function testOnlyOwnerShouldDisableWithdraw() public {
        (, , bool isWithdrawPaused, , , , ) = morpho.marketPauseStatus(cDai);
        assertFalse(isWithdrawPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsWithdrawPaused(cDai, true);

        morpho.setIsWithdrawPaused(cDai, true);
        (, , isWithdrawPaused, , , , ) = morpho.marketPauseStatus(cDai);
        assertTrue(isWithdrawPaused);
    }

    function testOnlyOwnerShouldDisableRepay() public {
        (, , , bool isRepayPaused, , , ) = morpho.marketPauseStatus(cDai);
        assertFalse(isRepayPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsRepayPaused(cDai, true);

        morpho.setIsRepayPaused(cDai, true);
        (, , , isRepayPaused, , , ) = morpho.marketPauseStatus(cDai);
        assertTrue(isRepayPaused);
    }

    function testOnlyOwnerShouldDisableLiquidateOnCollateral() public {
        (, , , , bool isLiquidateCollateralPaused, , ) = morpho.marketPauseStatus(cDai);
        assertFalse(isLiquidateCollateralPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsLiquidateCollateralPaused(cDai, true);

        morpho.setIsLiquidateCollateralPaused(cDai, true);
        (, , , , isLiquidateCollateralPaused, , ) = morpho.marketPauseStatus(cDai);
        assertTrue(isLiquidateCollateralPaused);
    }

    function testOnlyOwnerShouldDisableLiquidateOnBorrow() public {
        (, , , , , bool isLiquidateBorrowPaused, ) = morpho.marketPauseStatus(cDai);
        assertFalse(isLiquidateBorrowPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsLiquidateBorrowPaused(cDai, true);

        morpho.setIsLiquidateBorrowPaused(cDai, true);
        (, , , , , isLiquidateBorrowPaused, ) = morpho.marketPauseStatus(cDai);
        assertTrue(isLiquidateBorrowPaused);
    }

    function testOnlyOwnerCanIncreaseP2PDeltas() public {
        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.increaseP2PDeltas(cDai, 0);

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, 1_000 ether);
        supplier1.borrow(cDai, 2 ether);

        morpho.increaseP2PDeltas(cDai, 1 ether);
    }

    function testShouldNotIncreaseP2PDeltasWhenMarketNotCreated() public {
        hevm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.increaseP2PDeltas(address(1), 0);
    }

    function testIncreaseP2PDeltas() public {
        uint256 supplyAmount = 100 ether;
        uint256 borrowAmount = 50 ether;
        uint256 increaseDeltaAmount = 30 ether;

        supplier1.approve(wEth, supplyAmount);
        supplier1.supply(cEth, supplyAmount);
        supplier1.approve(dai, supplyAmount);
        supplier1.supply(cDai, supplyAmount);
        supplier1.borrow(cDai, borrowAmount);

        morpho.increaseP2PDeltas(cDai, increaseDeltaAmount);

        (uint256 p2pSupplyDelta, uint256 p2pBorrowDelta, , ) = morpho.deltas(cDai);

        assertEq(p2pSupplyDelta, increaseDeltaAmount.div(ICToken(cDai).exchangeRateStored()));
        assertEq(p2pBorrowDelta, increaseDeltaAmount.div(ICToken(cDai).borrowIndex()));
        assertApproxEqRel(
            ICToken(cDai).balanceOfUnderlying(address(morpho)),
            supplyAmount - borrowAmount + increaseDeltaAmount,
            1e8
        );
        assertApproxEqRel(
            ICToken(cDai).borrowBalanceCurrent(address(morpho)),
            increaseDeltaAmount,
            1e8
        );
    }

    function testIncreaseP2PDeltasMoreThanWhatIsPossibleSupply() public {
        uint256 supplyAmount = 100 ether;
        uint256 borrowAmount = 50 ether;
        uint256 deltaAmount = 25 ether;
        uint256 increaseDeltaAmount = 80 ether;

        supplier1.approve(wEth, type(uint256).max);
        supplier1.supply(cEth, supplyAmount);
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(cDai, supplyAmount);
        supplier1.borrow(cDai, borrowAmount);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        hevm.roll(block.number + 1);
        supplier1.repay(cDai, deltaAmount); // Creates a peer-to-peer supply delta.

        morpho.increaseP2PDeltas(cDai, increaseDeltaAmount);

        (uint256 p2pSupplyDelta, uint256 p2pBorrowDelta, , ) = morpho.deltas(cDai);

        assertApproxEqRel(
            p2pSupplyDelta,
            borrowAmount.div(ICToken(cDai).exchangeRateStored()),
            1e12
        );
        assertApproxEqRel(
            p2pBorrowDelta,
            (borrowAmount - deltaAmount).div(ICToken(cDai).borrowIndex()),
            1e12
        );
        assertApproxEqRel(ICToken(cDai).balanceOfUnderlying(address(morpho)), supplyAmount, 1e12);
        assertApproxEqRel(
            ICToken(cDai).borrowBalanceCurrent(address(morpho)),
            borrowAmount - deltaAmount,
            1e12
        );
    }

    function testIncreaseP2PDeltasMoreThanWhatIsPossibleBorrow() public {
        uint256 supplyAmount = 100 ether;
        uint256 borrowAmount = 50 ether;
        uint256 deltaAmount = 25 ether;
        uint256 increaseDeltaAmount = 80 ether;

        supplier1.approve(wEth, supplyAmount);
        supplier1.supply(cEth, supplyAmount);
        supplier1.approve(dai, supplyAmount);
        supplier1.supply(cDai, supplyAmount);
        supplier1.borrow(cDai, borrowAmount);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        supplier1.withdraw(cDai, supplyAmount - borrowAmount + deltaAmount); // Creates a peer-to-peer borrow delta.

        morpho.increaseP2PDeltas(cDai, increaseDeltaAmount);

        (uint256 p2pSupplyDelta, uint256 p2pBorrowDelta, , ) = morpho.deltas(cDai);

        assertApproxEqRel(
            p2pSupplyDelta,
            (borrowAmount - deltaAmount).div(ICToken(cDai).exchangeRateStored()),
            1e8
        );
        assertApproxEqRel(p2pBorrowDelta, borrowAmount.div(ICToken(cDai).borrowIndex()), 1e8);
        assertApproxEqRel(ICToken(cDai).balanceOfUnderlying(address(morpho)), deltaAmount, 1e8);
        assertApproxEqRel(ICToken(cDai).borrowBalanceCurrent(address(morpho)), borrowAmount, 1e8);
    }

    function testIncreaseP2PDeltasWithMaxBorrowDelta() public {
        uint256 supplyAmount = 100 ether;
        uint256 borrowAmount = 50 ether;
        uint256 increaseDeltaAmount = 80 ether;

        supplier1.approve(wEth, supplyAmount);
        supplier1.supply(cEth, supplyAmount);
        supplier1.approve(dai, supplyAmount);
        supplier1.supply(cDai, supplyAmount);
        supplier1.borrow(cDai, borrowAmount);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        supplier1.withdraw(cDai, type(uint256).max); // Creates a 100% peer-to-peer borrow delta.

        hevm.roll(block.number + 1000);

        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        morpho.increaseP2PDeltas(cDai, increaseDeltaAmount);
    }

    function testCallIncreaseP2PDeltasFromImplementation() public {
        vm.expectRevert();
        positionsManager.increaseP2PDeltasLogic(cDai, 0);
    }

    function testDeprecateCycle() public {
        hevm.expectRevert(abi.encodeWithSignature("BorrowNotPaused()"));
        morpho.setIsDeprecated(cDai, true);

        morpho.setIsBorrowPaused(cDai, true);
        morpho.setIsDeprecated(cDai, true);

        hevm.expectRevert(abi.encodeWithSignature("MarketIsDeprecated()"));
        morpho.setIsBorrowPaused(cDai, false);

        morpho.setIsDeprecated(cDai, false);
        morpho.setIsBorrowPaused(cDai, false);
    }
}
