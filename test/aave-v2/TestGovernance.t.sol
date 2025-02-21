// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestGovernance is TestSetup {
    using WadRayMath for uint256;

    function testShouldDeployContractWithTheRightValues() public {
        assertEq(address(morpho.entryPositionsManager()), address(entryPositionsManager));
        assertEq(address(morpho.exitPositionsManager()), address(exitPositionsManager));
        assertEq(address(morpho.interestRatesManager()), address(interestRatesManager));
        assertEq(address(morpho.addressesProvider()), address(poolAddressesProvider));
        assertEq(address(morpho.pool()), poolAddressesProvider.getLendingPool());
        assertEq(morpho.maxSortedUsers(), 20);

        (uint64 supply, uint64 borrow, uint64 withdraw, uint64 repay) = morpho
        .defaultMaxGasForMatching();
        assertEq(supply, 3e6);
        assertEq(borrow, 3e6);
        assertEq(withdraw, 3e6);
        assertEq(repay, 3e6);
    }

    function testShouldRevertWhenCreatingMarketWithAnImproperMarket() public {
        hevm.expectRevert(abi.encodeWithSignature("MarketIsNotListedOnAave()"));
        morpho.createMarket(address(supplier1), 3_333, 0);
    }

    function testOnlyOwnerCanCreateMarkets() public {
        hevm.expectRevert("Ownable: caller is not the owner");
        supplier1.createMarket(wEth, 3_333, 0);

        morpho.createMarket(wEth, 3_333, 0);
    }

    function testShouldCreateMarketWithRightParams() public {
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(wEth, 10_001, 0);
        hevm.expectRevert(abi.encodeWithSignature("ExceedsMaxBasisPoints()"));
        morpho.createMarket(wEth, 0, 10_001);

        morpho.createMarket(wEth, 1_000, 3_333);
        (address underlyingToken, uint16 reserveFactor, uint256 p2pIndexCursor, , , , ) = morpho
        .market(aWeth);
        assertEq(reserveFactor, 1_000);
        assertEq(p2pIndexCursor, 3_333);
        assertTrue(underlyingToken == wEth);
    }

    function testOnlyOwnerCanSetReserveFactor() public {
        for (uint256 i = 0; i < pools.length; i++) {
            hevm.expectRevert("Ownable: caller is not the owner");
            supplier1.setReserveFactor(aDai, 1111);

            hevm.expectRevert("Ownable: caller is not the owner");
            borrower1.setReserveFactor(aDai, 1111);
        }

        morpho.setReserveFactor(aDai, 1111);
    }

    function testReserveFactorShouldBeUpdatedWithRightValue() public {
        morpho.setReserveFactor(aDai, 1111);
        (, uint16 reserveFactor, , , , , ) = morpho.market(aDai);
        assertEq(reserveFactor, 1111);
    }

    function testShouldCreateMarketWithTheRightValues() public {
        morpho.createMarket(wEth, 3_333, 0);

        (, , , bool isCreated, , , ) = morpho.market(aWeth);

        assertTrue(isCreated);
        assertEq(morpho.p2pSupplyIndex(aWeth), WadRayMath.RAY);
        assertEq(morpho.p2pBorrowIndex(aWeth), WadRayMath.RAY);
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
        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsP2PDisabled(aDai, true);

        hevm.prank(address(supplier2));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsP2PDisabled(aDai, true);

        morpho.setIsP2PDisabled(aDai, true);
        (, , , , , , bool isP2PDisabled) = morpho.market(aDai);
        assertTrue(isP2PDisabled);
    }

    function testOnlyOwnerShouldSetEntryPositionsManager() public {
        IEntryPositionsManager entryPositionsManagerV2 = new EntryPositionsManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setEntryPositionsManager(entryPositionsManagerV2);

        morpho.setEntryPositionsManager(entryPositionsManagerV2);
        assertEq(address(morpho.entryPositionsManager()), address(entryPositionsManagerV2));
    }

    function testOnlyOwnerShouldSetInterestRatesManager() public {
        IInterestRatesManager interestRatesV2 = new InterestRatesManager();

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setInterestRatesManager(interestRatesV2);

        morpho.setInterestRatesManager(interestRatesV2);
        assertEq(address(morpho.interestRatesManager()), address(interestRatesV2));
    }

    function testOnlyOwnerShouldSetTreasuryVault() public {
        address treasuryVaultV2 = address(2);

        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setTreasuryVault(treasuryVaultV2);

        morpho.setTreasuryVault(treasuryVaultV2);
        assertEq(address(morpho.treasuryVault()), treasuryVaultV2);
    }

    function testOnlyOwnerCanSetPauseStatusForAllMarkets() public {
        hevm.prank(address(0));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsPausedForAllMarkets(true);

        morpho.setIsPausedForAllMarkets(true);
    }

    function testOnlyOwnerShouldSetDeprecatedMarket() public {
        morpho.setIsBorrowPaused(aDai, true);

        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsDeprecated(aDai, true);

        hevm.prank(address(supplier2));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.setIsDeprecated(aDai, true);

        morpho.setIsDeprecated(aDai, true);
        (, , , , , , bool isDeprecated) = morpho.marketPauseStatus(aDai);
        assertTrue(isDeprecated);

        morpho.setIsDeprecated(aDai, false);
        (, , , , , , isDeprecated) = morpho.marketPauseStatus(aDai);
        assertFalse(isDeprecated);
    }

    function testOnlyOwnerShouldDisableSupply() public {
        (bool isSupplyPaused, , , , , , ) = morpho.marketPauseStatus(aDai);
        assertFalse(isSupplyPaused);

        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsSupplyPaused(aDai, true);

        morpho.setIsSupplyPaused(aDai, true);
        (isSupplyPaused, , , , , , ) = morpho.marketPauseStatus(aDai);
        assertTrue(isSupplyPaused);
    }

    function testOnlyOwnerShouldDisableBorrow() public {
        (, bool isBorrowPaused, , , , , ) = morpho.marketPauseStatus(aDai);
        assertFalse(isBorrowPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsBorrowPaused(aDai, true);

        morpho.setIsBorrowPaused(aDai, true);
        (, isBorrowPaused, , , , , ) = morpho.marketPauseStatus(aDai);
        assertTrue(isBorrowPaused);
    }

    function testOnlyOwnerShouldDisableWithdraw() public {
        (, , bool isWithdrawPaused, , , , ) = morpho.marketPauseStatus(aDai);
        assertFalse(isWithdrawPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsWithdrawPaused(aDai, true);

        morpho.setIsWithdrawPaused(aDai, true);
        (, , isWithdrawPaused, , , , ) = morpho.marketPauseStatus(aDai);
        assertTrue(isWithdrawPaused);
    }

    function testOnlyOwnerShouldDisableRepay() public {
        (, , , bool isRepayPaused, , , ) = morpho.marketPauseStatus(aDai);
        assertFalse(isRepayPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsRepayPaused(aDai, true);

        morpho.setIsRepayPaused(aDai, true);
        (, , , isRepayPaused, , , ) = morpho.marketPauseStatus(aDai);
        assertTrue(isRepayPaused);
    }

    function testOnlyOwnerShouldDisableLiquidateOnCollateral() public {
        (, , , , bool isLiquidateCollateralPaused, , ) = morpho.marketPauseStatus(aDai);
        assertFalse(isLiquidateCollateralPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsLiquidateCollateralPaused(aDai, true);

        morpho.setIsLiquidateCollateralPaused(aDai, true);
        (, , , , isLiquidateCollateralPaused, , ) = morpho.marketPauseStatus(aDai);
        assertTrue(isLiquidateCollateralPaused);
    }

    function testOnlyOwnerShouldDisableLiquidateOnBorrow() public {
        (, , , , , bool isLiquidateBorrowPaused, ) = morpho.marketPauseStatus(aDai);
        assertFalse(isLiquidateBorrowPaused);
        vm.expectRevert("Ownable: caller is not the owner");
        supplier1.setIsLiquidateBorrowPaused(aDai, true);

        morpho.setIsLiquidateBorrowPaused(aDai, true);
        (, , , , , isLiquidateBorrowPaused, ) = morpho.marketPauseStatus(aDai);
        assertTrue(isLiquidateBorrowPaused);
    }

    function testOnlyOwnerCanIncreaseP2PDeltas() public {
        hevm.prank(address(supplier1));
        hevm.expectRevert("Ownable: caller is not the owner");
        morpho.increaseP2PDeltas(aDai, 0);

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, 1_000 ether);
        supplier1.borrow(aDai, 2 ether);

        morpho.increaseP2PDeltas(aDai, 1 ether);
    }

    function testShouldNotIncreaseP2PDeltasWhenMarketNotCreated() public {
        hevm.expectRevert(abi.encodeWithSignature("MarketNotCreated()"));
        morpho.increaseP2PDeltas(address(1), 0);
    }

    function testIncreaseP2PDeltas() public {
        uint256 supplyAmount = 100 ether;
        uint256 borrowAmount = 50 ether;
        uint256 increaseDeltaAmount = 30 ether;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(aUsdc, to6Decimals(supplyAmount));
        supplier1.approve(dai, supplyAmount);
        supplier1.supply(aDai, supplyAmount);
        supplier1.borrow(aDai, borrowAmount);

        morpho.increaseP2PDeltas(aDai, increaseDeltaAmount);

        (uint256 p2pSupplyDelta, uint256 p2pBorrowDelta, , ) = morpho.deltas(aDai);

        assertEq(p2pSupplyDelta, increaseDeltaAmount.rayDiv(pool.getReserveNormalizedIncome(dai)));
        assertEq(
            p2pBorrowDelta,
            increaseDeltaAmount.rayDiv(pool.getReserveNormalizedVariableDebt(dai))
        );
        assertApproxEqRel(
            IAToken(aDai).balanceOf(address(morpho)),
            supplyAmount - borrowAmount + increaseDeltaAmount,
            1e8
        );
        assertApproxEqRel(
            IVariableDebtToken(variableDebtDai).balanceOf(address(morpho)),
            increaseDeltaAmount,
            1e8
        );
    }

    function testIncreaseP2PDeltasMoreThanWhatIsPossibleSupply() public {
        uint256 supplyAmount = 101 ether;
        uint256 borrowAmount = 51 ether;
        uint256 deltaAmount = 25 ether;
        uint256 increaseDeltaAmount = 81 ether;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(aUsdc, to6Decimals(supplyAmount));
        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, supplyAmount);
        supplier1.borrow(aDai, borrowAmount);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        hevm.roll(block.number + 1);
        supplier1.repay(aDai, deltaAmount); // Creates a peer-to-peer supply delta.

        morpho.increaseP2PDeltas(aDai, increaseDeltaAmount);

        (uint256 p2pSupplyDelta, uint256 p2pBorrowDelta, , ) = morpho.deltas(aDai);

        assertApproxEqRel(
            p2pSupplyDelta,
            borrowAmount.rayDiv(pool.getReserveNormalizedIncome(dai)),
            1e12
        );
        assertApproxEqRel(
            p2pBorrowDelta,
            (borrowAmount - deltaAmount).rayDiv(pool.getReserveNormalizedVariableDebt(dai)),
            1e12
        );
        assertApproxEqRel(IAToken(aDai).balanceOf(address(morpho)), supplyAmount, 1e12);
        assertApproxEqRel(
            IVariableDebtToken(variableDebtDai).balanceOf(address(morpho)),
            borrowAmount - deltaAmount,
            1e12
        );
    }

    function testIncreaseP2PDeltasMoreThanWhatIsPossibleBorrow() public {
        uint256 supplyAmount = 101 ether;
        uint256 borrowAmount = 51 ether;
        uint256 deltaAmount = 25 ether;
        uint256 increaseDeltaAmount = 81 ether;

        supplier1.approve(usdc, type(uint256).max);
        supplier1.supply(aUsdc, to6Decimals(supplyAmount));
        supplier1.approve(dai, supplyAmount);
        supplier1.supply(aDai, supplyAmount);
        supplier1.borrow(aDai, borrowAmount);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        supplier1.withdraw(aDai, supplyAmount - borrowAmount + deltaAmount); // Creates a peer-to-peer borrow delta.

        morpho.increaseP2PDeltas(aDai, increaseDeltaAmount);

        (uint256 p2pSupplyDelta, uint256 p2pBorrowDelta, , ) = morpho.deltas(aDai);

        assertApproxEqRel(
            p2pSupplyDelta,
            (borrowAmount - deltaAmount).rayDiv(pool.getReserveNormalizedIncome(dai)),
            1e8,
            "1"
        );
        assertApproxEqRel(
            p2pBorrowDelta,
            borrowAmount.rayDiv(pool.getReserveNormalizedVariableDebt(dai)),
            1e8,
            "2"
        );
        assertApproxEqRel(
            IAToken(aDai).balanceOf(address(morpho)),
            borrowAmount - deltaAmount,
            1e8,
            "3"
        );
        assertApproxEqRel(
            IVariableDebtToken(variableDebtDai).balanceOf(address(morpho)),
            borrowAmount,
            1e8,
            "4"
        );
    }

    function testIncreaseP2PDeltasWithMaxBorrowDelta() public {
        uint256 supplyAmount = 100 ether;
        uint256 borrowAmount = 50 ether;
        uint256 increaseDeltaAmount = 80 ether;

        createMarket(aWeth);
        supplier1.approve(wEth, supplyAmount);
        supplier1.supply(aWeth, supplyAmount);
        supplier1.approve(dai, supplyAmount);
        supplier1.supply(aDai, supplyAmount);
        supplier1.borrow(aDai, borrowAmount);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        supplier1.withdraw(aDai, type(uint256).max); // Creates a 100% peer-to-peer borrow delta.

        hevm.warp(block.timestamp + 5 days);

        hevm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        morpho.increaseP2PDeltas(aDai, increaseDeltaAmount);
    }

    function testCallIncreaseP2PDeltasFromImplementation() public {
        vm.expectRevert();
        exitPositionsManager.increaseP2PDeltasLogic(aDai, 0);
    }

    function testDeprecateCycle() public {
        hevm.expectRevert(abi.encodeWithSignature("BorrowNotPaused()"));
        morpho.setIsDeprecated(aDai, true);

        morpho.setIsBorrowPaused(aDai, true);
        morpho.setIsDeprecated(aDai, true);

        hevm.expectRevert(abi.encodeWithSignature("MarketIsDeprecated()"));
        morpho.setIsBorrowPaused(aDai, false);

        morpho.setIsDeprecated(aDai, false);
        morpho.setIsBorrowPaused(aDai, false);
    }
}
