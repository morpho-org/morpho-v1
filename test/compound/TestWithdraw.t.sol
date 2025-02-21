// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Attacker} from "./helpers/Attacker.sol";
import "./setup/TestSetup.sol";

contract TestWithdraw is TestSetup {
    using CompoundMath for uint256;

    // The user withdrawal leads to an under-collateralized position, the withdrawal reverts.
    function testWithdraw1() public {
        uint256 amount = 10000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        borrower1.borrow(cDai, amount);

        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedWithdraw()"));
        borrower1.withdraw(cUsdc, to6Decimals(collateral));
    }

    // The supplier withdraws less than his `onPool` balance. The liquidity is taken from his `onPool` balance.
    function testWithdraw2() public {
        uint256 amount = 10000 ether;

        supplier1.approve(usdc, to6Decimals(2 * amount));
        supplier1.supply(cUsdc, to6Decimals(2 * amount));

        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        uint256 expectedOnPool = to6Decimals(2 * amount).div(ICToken(cUsdc).exchangeRateCurrent());

        assertEq(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(cUsdc, to6Decimals(amount));

        (inP2P, onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        assertEq(inP2P, 0);
        testEquality(onPool, expectedOnPool / 2);
    }

    // The supplier withdraws all its `onPool` balance.
    function testWithdrawAll() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(usdc, to6Decimals(amount));
        supplier1.supply(cUsdc, to6Decimals(amount));

        uint256 balanceBefore = supplier1.balanceOf(usdc);
        (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        uint256 expectedOnPool = to6Decimals(amount).div(ICToken(cUsdc).exchangeRateCurrent());

        assertEq(inP2P, 0);
        testEquality(onPool, expectedOnPool);

        supplier1.withdraw(cUsdc, type(uint256).max);

        uint256 balanceAfter = supplier1.balanceOf(usdc);
        (inP2P, onPool) = morpho.supplyBalanceInOf(cUsdc, address(supplier1));

        assertEq(inP2P, 0, "in peer-to-peer");
        assertApproxEqAbs(onPool, 0, 1e5, "on Pool");
        testEquality(balanceAfter - balanceBefore, to6Decimals(amount), "balance");
    }

    // There is a supplier `onPool` available to replace him `inP2P`. First, his liquidity `onPool` is taken, his matched is replaced by the available supplier up to his withdrawal amount.
    function testWithdraw3_1() public {
        uint256 borrowedAmount = 10000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount / 2).div(ICToken(cDai).exchangeRateCurrent());
        uint256 expectedInP2P = (suppliedAmount / 2).div(morpho.p2pSupplyIndex(cDai));

        testEquality(onPoolSupplier, expectedOnPool);
        assertEq(onPoolBorrower1, 0);
        assertEq(inP2PSupplier, expectedInP2P);

        // An available supplier onPool
        supplier2.approve(dai, suppliedAmount);
        supplier2.supply(cDai, suppliedAmount);

        // supplier withdraws suppliedAmount
        supplier1.withdraw(cDai, suppliedAmount);

        // Check balances for supplier1
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        assertEq(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for supplier2
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier2));
        expectedInP2P = (suppliedAmount / 2).div(morpho.p2pSupplyIndex(cDai));
        assertApproxEqAbs(onPoolSupplier, expectedOnPool, 1);
        assertApproxEqAbs(inP2PSupplier, expectedInP2P, 1);

        // Check balances for borrower1
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(cDai, address(borrower1));
        expectedInP2P = (suppliedAmount / 2).div(morpho.p2pBorrowIndex(cDai));
        assertEq(onPoolBorrower1, 0);
        assertApproxEqAbs(inP2PBorrower1, expectedInP2P, 1);
    }

    // There are NMAX (or less) suppliers `onPool` available to replace him `inP2P`, they supply enough to cover for the withdrawn liquidity. First, his liquidity `onPool` is taken, his matched is replaced by NMAX (or less) suppliers up to his withdrawal amount.
    function testWithdraw3_2() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 borrowedAmount = 100_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );
        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount / 2).div(ICToken(cDai).exchangeRateCurrent());
        uint256 expectedInP2P = (suppliedAmount / 2).div(morpho.p2pSupplyIndex(cDai));

        testEquality(onPoolSupplier, expectedOnPool);
        assertEq(onPoolBorrower, 0);
        assertEq(inP2PSupplier, expectedInP2P);

        // NMAX-1 suppliers have up to suppliedAmount waiting on pool
        uint256 NMAX = 20;
        createSigners(NMAX);

        // minus 1 because supplier1 must not be counted twice !
        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (NMAX - 1);

        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        // supplier1 withdraws suppliedAmount.
        supplier1.withdraw(cDai, type(uint256).max);

        // Check balances for supplier1.
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
        assertEq(onPoolSupplier, 0);
        testEquality(inP2PSupplier, 0);

        // Check balances for the borrower.
        (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowBalanceInP2P = borrowedAmount.div(morpho.p2pBorrowIndex(cDai));

        testEquality(inP2PBorrower, expectedBorrowBalanceInP2P, "borrower in peer-to-peer");
        assertApproxEqAbs(onPoolBorrower, 0, 1e10, "borrower on Pool");

        // Now test for each individual supplier that replaced the original.
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(cDai, address(suppliers[i]));
            expectedInP2P = amountPerSupplier.div(morpho.p2pSupplyIndex(cDai));

            testEquality(inP2P, expectedInP2P, "in peer-to-peer");
            assertEq(onPool, 0, "on pool");
        }
    }

    // There are no suppliers `onPool` to replace him `inP2P`. After withdrawing the amount `onPool`, his peer-to-peer credit lines will be broken and the corresponding borrower(s) will be unmatched and placed on pool.
    function testWithdraw3_3() public {
        uint256 borrowedAmount = 10_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for borrowedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount / 2).div(ICToken(cDai).exchangeRateCurrent());
        uint256 expectedInP2P = (suppliedAmount / 2).div(morpho.p2pSupplyIndex(cDai));

        testEquality(onPoolSupplier, expectedOnPool);
        assertEq(onPoolBorrower, 0);
        assertEq(inP2PSupplier, expectedInP2P);

        // Supplier1 withdraws 75% of supplied amount
        uint256 toWithdraw = (75 * suppliedAmount) / 100;
        supplier1.withdraw(cDai, toWithdraw);

        // Check balances for the borrower
        (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(cDai, address(borrower1));

        uint256 expectedBorrowBalanceInP2P = (borrowedAmount / 2).div(morpho.p2pBorrowIndex(cDai));

        // The amount withdrawn from supplier1 minus what is on pool will be removed from the borrower peer-to-peer's position.
        uint256 expectedBorrowBalanceOnPool = (toWithdraw -
            onPoolSupplier.mul(ICToken(cDai).exchangeRateCurrent()))
        .div(ICToken(cDai).borrowIndex());

        assertApproxEqAbs(inP2PBorrower, expectedBorrowBalanceInP2P, 1, "borrower in peer-to-peer");
        assertApproxEqAbs(onPoolBorrower, expectedBorrowBalanceOnPool, 1e4, "borrower on Pool");

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));

        uint256 expectedSupplyBalanceInP2P = ((25 * suppliedAmount) / 100).div(
            morpho.p2pSupplyIndex(cDai)
        );

        assertApproxEqAbs(inP2PSupplier, expectedSupplyBalanceInP2P, 2, "supplier in peer-to-peer");
        assertEq(onPoolSupplier, 0, "supplier on Pool");
    }

    // The supplier is matched to 2 x NMAX borrowers. There are NMAX suppliers `onPool` available to replace him `inP2P`, they don't supply enough to cover the withdrawn liquidity. First, the `onPool` liquidity is withdrawn, then we proceed to NMAX `match supplier`. Finally, we proceed to NMAX `unmatch borrower` for an amount equal to the remaining to withdraw.
    function testWithdraw3_4() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 borrowedAmount = 100_000 ether;
        uint256 suppliedAmount = 2 * borrowedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));
        borrower1.borrow(cDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1.
        (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
            cDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier1)
        );

        uint256 expectedOnPool = (suppliedAmount / 2).div(ICToken(cDai).exchangeRateCurrent());
        uint256 expectedInP2P = (suppliedAmount / 2).div(morpho.p2pSupplyIndex(cDai));

        testEquality(onPoolSupplier, expectedOnPool, "supplier on Pool 1");
        assertEq(onPoolBorrower, 0, "borrower on Pool 1");
        assertEq(inP2PSupplier, expectedInP2P, "supplier in peer-to-peer 1");

        // NMAX-1 suppliers have up to suppliedAmount/2 waiting on pool
        uint256 NMAX = 20;
        createSigners(NMAX);

        // minus 1 because supplier1 must not be counted twice !
        uint256 amountPerSupplier = (suppliedAmount - borrowedAmount) / (2 * (NMAX - 1));
        uint256[] memory rates = new uint256[](NMAX);

        uint256 matchedAmount;
        for (uint256 i = 0; i < NMAX; i++) {
            if (suppliers[i] == supplier1) continue;

            rates[i] = ICToken(cDai).exchangeRateCurrent();

            matchedAmount += getBalanceOnCompound(
                amountPerSupplier,
                ICToken(cDai).exchangeRateCurrent()
            );

            suppliers[i].approve(dai, amountPerSupplier);
            suppliers[i].supply(cDai, amountPerSupplier);
        }

        // supplier withdraws suppliedAmount.
        supplier1.withdraw(cDai, suppliedAmount);

        uint256 halfBorrowedAmount = borrowedAmount / 2;

        {
            // Check balances for supplier1.
            (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
            assertEq(onPoolSupplier, 0, "supplier on Pool 2");
            testEquality(inP2PSupplier, 0, "supplier in peer-to-peer 2");

            (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(cDai, address(borrower1));

            uint256 expectedBorrowBalanceInP2P = halfBorrowedAmount.div(
                morpho.p2pBorrowIndex(cDai)
            );
            uint256 expectedBorrowBalanceOnPool = halfBorrowedAmount.div(
                ICToken(cDai).borrowIndex()
            );

            assertApproxEqAbs(
                inP2PBorrower,
                expectedBorrowBalanceInP2P,
                10,
                "borrower in peer-to-peer 2"
            );
            assertApproxEqAbs(
                onPoolBorrower,
                expectedBorrowBalanceOnPool,
                1e10,
                "borrower on Pool 2"
            );
        }

        // Check balances for the borrower.

        uint256 inP2P;
        uint256 onPool;

        // Now test for each individual supplier that replaced the original.
        for (uint256 i = 0; i < suppliers.length; i++) {
            if (suppliers[i] == supplier1) continue;

            (inP2P, onPool) = morpho.supplyBalanceInOf(cDai, address(suppliers[i]));

            assertEq(
                inP2P,
                getBalanceOnCompound(amountPerSupplier, rates[i]).div(morpho.p2pSupplyIndex(cDai)),
                "supplier in peer-to-peer"
            );
            assertEq(onPool, 0, "supplier on pool");

            (inP2P, onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));
            assertEq(inP2P, 0, "borrower in peer-to-peer");
        }
    }

    struct Vars {
        uint256 LR;
        uint256 BPY;
        uint256 VBR;
        uint256 NVD;
        uint256 BP2PD;
        uint256 BP2PA;
        uint256 BP2PER;
    }

    function testDeltaWithdraw() public {
        // Allows only 10 unmatch borrowers.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 9e5, 3e6);

        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = 20 * borrowedAmount;
        uint256 expectedSupplyBalanceInP2P;

        // supplier1 and 20 borrowers are matched for suppliedAmount.
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        createSigners(30);
        uint256 matched;

        // 2 * NMAX borrowers borrow borrowedAmount.
        for (uint256 i; i < 20; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, borrowedAmount, type(uint64).max);
            matched += borrowedAmount.div(morpho.p2pBorrowIndex(cDai));
        }

        {
            uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(cDai);
            expectedSupplyBalanceInP2P = suppliedAmount.div(p2pSupplyIndex);

            // Check balances after match of supplier1 and borrowers.
            (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
                cDai,
                address(supplier1)
            );
            assertApproxEqAbs(onPoolSupplier, 0, 20, "supplier on pool");
            assertApproxEqAbs(inP2PSupplier, expectedSupplyBalanceInP2P, 20, "supplier in P2P");

            uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(cDai);
            uint256 expectedBorrowBalanceInP2P = borrowedAmount.div(p2pBorrowIndex);
            uint256 inP2PBorrower;
            uint256 onPoolBorrower;

            for (uint256 i = 10; i < 20; i++) {
                (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(
                    cDai,
                    address(borrowers[i])
                );
                assertEq(onPoolBorrower, 0);
                assertEq(inP2PBorrower, expectedBorrowBalanceInP2P, "borrower in P2P");
            }

            // Supplier withdraws max.
            // Should create a delta on borrowers side.
            supplier1.withdraw(cDai, type(uint256).max);

            // Check balances for supplier1.
            (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier1));
            assertEq(onPoolSupplier, 0);
            testEquality(inP2PSupplier, 0);

            // There should be a delta.
            // The amount unmatched during the withdraw.
            uint256 unmatched = 10 * inP2PBorrower.mul(morpho.p2pBorrowIndex(cDai));
            // The difference between the previous matched amount and the amout unmatched creates a delta.
            uint256 expectedP2PBorrowDeltaInUnderlying = (matched.mul(morpho.p2pBorrowIndex(cDai)) -
                unmatched);
            uint256 expectedP2PBorrowDelta = (matched.mul(morpho.p2pBorrowIndex(cDai)) - unmatched)
            .div(ICToken(cDai).borrowIndex());

            (, uint256 p2pBorrowDelta, , ) = morpho.deltas(cDai);
            assertEq(p2pBorrowDelta, expectedP2PBorrowDelta, "borrow delta not expected 1");

            // Borrow delta matching by new supplier.
            supplier2.approve(dai, expectedP2PBorrowDeltaInUnderlying / 2);
            supplier2.supply(cDai, expectedP2PBorrowDeltaInUnderlying / 2);

            (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(cDai, address(supplier2));
            expectedSupplyBalanceInP2P = (expectedP2PBorrowDeltaInUnderlying / 2).div(
                morpho.p2pSupplyIndex(cDai)
            );

            (, p2pBorrowDelta, , ) = morpho.deltas(cDai);
            testEquality(p2pBorrowDelta, expectedP2PBorrowDelta / 2, "borrow delta not expected 2");
            assertEq(onPoolSupplier, 0, "on pool supplier not 0");
            testEquality(
                inP2PSupplier,
                expectedSupplyBalanceInP2P,
                "in peer-to-peer supplier not expected"
            );
        }

        {
            Vars memory oldVars;
            Vars memory newVars;

            (, oldVars.BP2PD, , oldVars.BP2PA) = morpho.deltas(cDai);
            oldVars.NVD = ICToken(cDai).borrowIndex();
            oldVars.BP2PER = morpho.p2pBorrowIndex(cDai);
            (, oldVars.BPY) = getApproxP2PRates(cDai);

            move1000BlocksForward(cDai);

            (, newVars.BP2PD, , newVars.BP2PA) = morpho.deltas(cDai);
            newVars.NVD = ICToken(cDai).borrowIndex();
            newVars.BP2PER = morpho.p2pBorrowIndex(cDai);
            (, newVars.BPY) = getApproxP2PRates(cDai);
            newVars.LR = ICToken(cDai).supplyRatePerBlock();
            newVars.VBR = ICToken(cDai).borrowRatePerBlock();

            uint256 shareOfTheDelta = newVars.BP2PD.mul(newVars.NVD).div(oldVars.BP2PER).div(
                newVars.BP2PA
            );

            uint256 expectedBP2PER = oldVars.BP2PER.mul(
                _computeCompoundedInterest(oldVars.BPY, 1000).mul(WAD - shareOfTheDelta) +
                    shareOfTheDelta.mul(newVars.NVD).div(oldVars.NVD)
            );

            assertApproxEqAbs(
                expectedBP2PER,
                newVars.BP2PER,
                (expectedBP2PER * 2) / 100,
                "BP2PER not expected"
            );

            uint256 expectedBorrowBalanceInUnderlying = borrowedAmount.div(oldVars.BP2PER).mul(
                expectedBP2PER
            );

            for (uint256 i = 10; i < 20; i++) {
                (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
                    cDai,
                    address(borrowers[i])
                );
                assertApproxEqAbs(
                    inP2PBorrower.mul(newVars.BP2PER),
                    expectedBorrowBalanceInUnderlying,
                    (expectedBorrowBalanceInUnderlying * 2) / 100,
                    "not expected underlying balance"
                );
                assertEq(onPoolBorrower, 0);
            }
        }

        // Borrow delta reduction with borrowers repaying
        for (uint256 i = 10; i < 20; i++) {
            borrowers[i].approve(dai, borrowedAmount);
            borrowers[i].repay(cDai, borrowedAmount);
        }

        (, uint256 p2pBorrowDeltaAfter, , ) = morpho.deltas(cDai);
        assertApproxEqAbs(p2pBorrowDeltaAfter, 0, 1, "borrow delta 2");

        (uint256 inP2PSupplier2, uint256 onPoolSupplier2) = morpho.supplyBalanceInOf(
            cDai,
            address(supplier2)
        );

        testEquality(inP2PSupplier2, expectedSupplyBalanceInP2P);
        assertEq(onPoolSupplier2, 0);
    }

    function testDeltaWithdrawAll() public {
        // Allows only 10 unmatch borrowers.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 9e5, 3e6);

        uint256 borrowedAmount = 1 ether;
        uint256 collateral = 2 * borrowedAmount;
        uint256 suppliedAmount = 20 * borrowedAmount + 1e12;

        // supplier1 and 20 borrowers are matched for suppliedAmount.
        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(cDai, suppliedAmount);

        createSigners(20);

        // 2 * NMAX borrowers borrow borrowedAmount.
        for (uint256 i = 0; i < 20; i++) {
            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(cUsdc, to6Decimals(collateral));
            borrowers[i].borrow(cDai, borrowedAmount + i, type(uint64).max);
        }

        for (uint256 i = 0; i < 20; i++) {
            (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));
            assertEq(inP2P, (borrowedAmount + i).div(morpho.p2pBorrowIndex(cDai)), "inP2P");
            assertEq(onPool, 0, "onPool");
        }

        // Supplier withdraws max.
        // Should create a delta on borrowers side.
        supplier1.withdraw(cDai, type(uint256).max);

        for (uint256 i = 0; i < 10; i++) {
            (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));
            assertEq(inP2P, 0, string.concat("inP2P", Strings.toString(i)));
            assertApproxEqAbs(
                onPool,
                (borrowedAmount + i).div(ICToken(cDai).borrowIndex()),
                1e8,
                string.concat("onPool", Strings.toString(i))
            );
        }
        for (uint256 i = 10; i < 20; i++) {
            (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));
            assertEq(
                inP2P,
                (borrowedAmount + i).div(morpho.p2pBorrowIndex(cDai)),
                string.concat("inP2P", Strings.toString(i))
            );
            assertEq(onPool, 0, string.concat("onPool", Strings.toString(i)));
        }

        (
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount
        ) = morpho.deltas(cDai);

        assertEq(p2pSupplyDelta, 0, "p2pSupplyDelta");
        assertApproxEqAbs(
            p2pBorrowDelta,
            (10 * borrowedAmount).div(ICToken(cDai).borrowIndex()),
            1e9,
            "p2pBorrowDelta"
        );
        assertApproxEqAbs(p2pSupplyAmount, 0, 1, "p2pSupplyAmount");
        assertApproxEqAbs(
            p2pBorrowAmount,
            (10 * borrowedAmount).div(morpho.p2pBorrowIndex(cDai)),
            1e2,
            "p2pBorrowAmount"
        );

        move1000BlocksForward(cDai);

        for (uint256 i = 0; i < 20; i++) {
            borrowers[i].approve(dai, type(uint256).max);
            borrowers[i].repay(cDai, type(uint256).max);
            borrowers[i].withdraw(cUsdc, type(uint256).max);
        }

        for (uint256 i = 0; i < 20; i++) {
            (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(cDai, address(borrowers[i]));
            assertEq(inP2P, 0, "inP2P");
            assertEq(onPool, 0, "onPool");
        }
    }

    function testShouldNotWithdrawWhenUnderCollaterized() public {
        uint256 toSupply = 100 ether;
        uint256 toBorrow = toSupply / 2;

        // supplier1 deposits collateral.
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        // supplier2 deposits collateral.
        supplier2.approve(dai, toSupply);
        supplier2.supply(cDai, toSupply);

        // supplier1 tries to withdraw more than allowed.
        supplier1.borrow(cUsdc, to6Decimals(toBorrow));
        hevm.expectRevert(abi.encodeWithSignature("UnauthorisedWithdraw()"));
        supplier1.withdraw(cDai, toSupply);
    }

    // Test attack.
    // Should be possible to withdraw amount while an attacker sends cToken to trick Morpho contract.
    function testWithdrawWhileAttackerSendsCToken() public {
        Attacker attacker = new Attacker();
        deal(dai, address(attacker), type(uint256).max / 2);

        uint256 toSupply = 100 ether;
        uint256 collateral = 2 * toSupply;
        uint256 toBorrow = toSupply;

        // Attacker sends cToken to morpho contract.
        attacker.approve(dai, cDai, toSupply);
        attacker.deposit(cDai, toSupply);
        attacker.transfer(dai, address(morpho), toSupply);

        // supplier1 deposits collateral.
        supplier1.approve(dai, toSupply);
        supplier1.supply(cDai, toSupply);

        // borrower1 deposits collateral.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(cUsdc, to6Decimals(collateral));

        // supplier1 tries to withdraw.
        borrower1.borrow(cDai, toBorrow);
        supplier1.withdraw(cDai, toSupply);
    }

    function testShouldNotWithdrawZero() public {
        hevm.expectRevert(PositionsManager.AmountIsZero.selector);
        morpho.withdraw(cDai, 0);
    }

    function testWithdrawnOnPoolThreshold() public {
        uint256 amountWithdrawn = 1e6;

        supplier1.approve(dai, 1 ether);
        supplier1.supply(cDai, 1 ether);

        hevm.expectRevert(abi.encodeWithSignature("WithdrawTooSmall()"));
        supplier1.withdraw(cDai, amountWithdrawn);
    }

    function testShouldNotFreezeMarketWithExchangeRatePump() public {
        uint256 amount = 500_000e6;
        supplier1.approve(usdc, amount);
        supplier1.supply(cUsdc, amount);

        hevm.roll(block.number + 1);

        hevm.prank(address(supplier1));
        ERC20(usdc).transfer(cUsdc, 200e6);

        supplier1.withdraw(cUsdc, type(uint256).max);
    }

    function testShouldBeAbleToWithdrawAfterDelayWhenPartiallyMatched() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, amount);
        supplier1.supply(cDai, amount);

        borrower1.approve(wEth, amount);
        borrower1.supply(cEth, amount);
        borrower1.borrow(cDai, amount / 2);

        hevm.roll(block.number + 100);

        supplier1.withdraw(cDai, type(uint256).max);
    }

    function testShouldWithdrawToReceiver() public {
        uint256 amount = 10_000 ether;

        supplier1.approve(dai, 2 * amount);
        supplier1.supply(cDai, 2 * amount);

        uint256 balanceBefore = ERC20(dai).balanceOf(address(supplier2));

        supplier1.withdraw(cDai, amount, address(supplier2));

        assertEq(ERC20(dai).balanceOf(address(supplier2)), balanceBefore + amount);
    }

    function testShouldPreventWithdrawWhenBorrowCapReached() public {
        createMarket(cUni);

        uint256 compoundCollateralAmount = 50_000_000 ether;
        deal(uni, address(borrower1), compoundCollateralAmount);
        borrower1.compoundSupply(cUni, compoundCollateralAmount);
        borrower1.compoundBorrow(
            cUni,
            morpho.comptroller().borrowCaps(cUni) - ICToken(cUni).totalBorrows() - 1 ether
        );

        deal(uni, address(supplier1), 110 ether);
        supplier1.approve(uni, 110 ether);
        supplier1.supply(cUni, 110 ether);

        deal(dai, address(borrower2), 100_000 ether);
        borrower2.approve(dai, 100_000 ether);
        borrower2.supply(cDai, 100_000 ether);
        borrower2.borrow(cUni, 100 ether);

        vm.expectRevert("market borrow cap reached");
        supplier1.withdraw(cUni, type(uint256).max);
    }
}
