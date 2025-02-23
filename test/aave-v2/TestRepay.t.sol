// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestRepay is TestSetup {
    using SafeTransferLib for ERC20;
    using WadRayMath for uint256;

    // The borrower repays no more than his `onPool` balance. The liquidity is repaid on his `onPool` balance.
    function testRepay1() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        borrower1.approve(dai, amount);
        borrower1.repay(aDai, amount);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
    }

    function testRepayAll() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        uint256 balanceBefore = borrower1.balanceOf(dai);
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrower1));
        uint256 balanceAfter = supplier1.balanceOf(dai);

        testEquality(inP2P, 0);
        testEquality(onPool, 0);
        testEquality(balanceBefore - balanceAfter, amount);
    }

    // There is a borrower `onPool` available to replace him `inP2P`. First, his debt `onPool` is repaid, his matched debt is replaced by the available borrower up to his repaid amount.
    function testRepay2_1() public {
        uint256 suppliedAmount = 10_000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = suppliedAmount.rayDiv(pool.getReserveNormalizedVariableDebt(dai));

        testEquality(onPoolSupplier, 0, "supplier on pool");
        testEquality(onPoolBorrower1, expectedOnPool, "borrower on pool");
        testEquality(inP2PSupplier, inP2PBorrower1, "equality");

        // An available borrower onPool
        uint256 availableBorrowerAmount = borrowedAmount / 4;
        borrower2.approve(usdc, to6Decimals(collateral));
        borrower2.supply(aUsdc, to6Decimals(collateral));
        borrower2.borrow(aDai, availableBorrowerAmount);

        // Borrower1 repays 75% of suppliedAmount
        borrower1.approve(dai, (75 * borrowedAmount) / 100);
        borrower1.repay(aDai, (75 * borrowedAmount) / 100);

        // Check balances for borrower1 & borrower2
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        (uint256 inP2PAvailableBorrower, uint256 onPoolAvailableBorrower) = morpho
        .borrowBalanceInOf(aDai, address(borrower2));
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
        uint256 expectedBorrowBalanceInP2P = ((25 * borrowedAmount) / 100).rayDiv(p2pBorrowIndex);

        testEquality(inP2PBorrower1, inP2PAvailableBorrower);
        testEquality(inP2PBorrower1, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower1, 0);
        testEquality(onPoolAvailableBorrower, 0);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier1));
        testEquality(2 * inP2PBorrower1, inP2PSupplier);
        testEquality(onPoolSupplier, 0);
    }

    // There are NMAX (or less) borrowers `onPool` available to replace him `inP2P`, they borrow enough to cover for the repaid liquidity. First, his debt `onPool` is repaid, his matched liquidity is replaced by NMAX (or less) borrowers up to his repaid amount.
    function testRepay2_2() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 suppliedAmount = 10_000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched up to suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        testEquality(onPoolSupplier, 0);
        testEquality(
            onPoolBorrower1,
            suppliedAmount.rayDiv(pool.getReserveNormalizedVariableDebt(dai))
        );
        testEquality(inP2PSupplier, inP2PBorrower1);

        // NMAX borrowers have debt waiting on pool
        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 normalizedVariableDebt = pool.getReserveNormalizedVariableDebt(dai);
        // Minus because borrower1 must not be counted twice !
        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (NMAX - 1);

        for (uint256 i; i < NMAX; i++) {
            if (borrowers[i] == borrower1) continue;

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);

            (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrowers[i]));

            testEquality(inP2P, 0);
            testEquality(onPool, amountPerBorrower.rayDiv(normalizedVariableDebt));
        }

        // Borrower1 repays all of his debt
        borrower1.approve(dai, borrowedAmount);
        borrower1.repay(aDai, borrowedAmount);

        // His balance should be set to 0
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PBorrower1, 0);

        // Check balances for the supplier
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);

        testEquality(inP2PSupplier, suppliedAmount.rayDiv(p2pBorrowIndex));
        testEquality(onPoolSupplier, 0);

        // Now test for each individual borrower that replaced the original
        for (uint256 i; i < borrowers.length; i++) {
            if (borrowers[i] == borrower1) continue;

            (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrowers[i]));

            testEquality(amountPerBorrower, inP2P.rayMul(p2pBorrowIndex));
            testEquality(onPool, 0);
        }
    }

    // There are no borrowers `onPool` to replace him `inP2P`. After repaying the amount `onPool`, his P2P credit line will be broken and the corresponding supplier(s) will be unmatched, and placed on pool.
    function testRepay2_3() public {
        uint256 suppliedAmount = 10_000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for supplierAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        uint256 expectedOnPool = suppliedAmount.rayDiv(pool.getReserveNormalizedVariableDebt(dai));

        testEquality(onPoolSupplier, 0);
        testEquality(onPoolBorrower1, expectedOnPool);
        testEquality(inP2PSupplier, inP2PBorrower1);

        // Borrower1 repays 75% of borrowed amount
        borrower1.approve(dai, (75 * borrowedAmount) / 100);
        borrower1.repay(aDai, (75 * borrowedAmount) / 100);

        // Check balances for borrower
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        uint256 normalizedIncome = pool.getReserveNormalizedIncome(dai);
        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);

        uint256 expectedBorrowBalanceInP2P = ((25 * borrowedAmount) / 100).rayDiv(p2pBorrowIndex);

        testEquality(inP2PBorrower1, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower1, 0);

        // Check balances for supplier
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        uint256 expectedSupplyBalanceInP2P = (suppliedAmount / 2).rayDiv(p2pBorrowIndex);
        uint256 expectedSupplyBalanceOnPool = (suppliedAmount / 2).rayDiv(normalizedIncome);

        testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
        testEquality(onPoolSupplier, expectedSupplyBalanceOnPool);
    }

    // The borrower is matched to 2 x NMAX suppliers. There are NMAX borrowers `onPool` available to replace him `inP2P`, they don't supply enough to cover for the repaid liquidity. First, the `onPool` liquidity is repaid, then we proceed to NMAX `match borrower`. Finally, we proceed to NMAX `unmatch supplier` for an amount equal to the remaining to withdraw.
    function testRepay2_4() public {
        setDefaultMaxGasForMatchingHelper(
            type(uint64).max,
            type(uint64).max,
            type(uint64).max,
            type(uint64).max
        );

        uint256 suppliedAmount = 10_000 ether;
        uint256 borrowedAmount = 2 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;

        // Borrower1 & supplier1 are matched for suppliedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        supplier1.approve(dai, suppliedAmount);
        supplier1.supply(aDai, suppliedAmount);

        // Check balances after match of borrower1 & supplier1
        (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower1)
        );

        (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
            aDai,
            address(supplier1)
        );

        testEquality(onPoolSupplier, 0);
        testEquality(
            onPoolBorrower1,
            suppliedAmount.rayDiv(pool.getReserveNormalizedVariableDebt(dai))
        );
        testEquality(inP2PSupplier, inP2PBorrower1);

        // NMAX borrowers have borrowerAmount/2 (cumulated) of debt waiting on pool
        uint256 NMAX = 20;
        createSigners(NMAX);

        uint256 amountPerBorrower = (borrowedAmount - suppliedAmount) / (2 * (NMAX - 1));
        // minus because borrower1 must not be counted twice !
        for (uint256 i = 0; i < NMAX; i++) {
            if (borrowers[i] == borrower1) continue;

            borrowers[i].approve(usdc, to6Decimals(collateral));
            borrowers[i].supply(aUsdc, to6Decimals(collateral));
            borrowers[i].borrow(aDai, amountPerBorrower);
        }

        // Borrower1 repays all of his debt
        borrower1.approve(dai, borrowedAmount);
        borrower1.repay(aDai, borrowedAmount);

        // His balance should be set to 0
        (inP2PBorrower1, onPoolBorrower1) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        testEquality(onPoolBorrower1, 0);
        testEquality(inP2PBorrower1, 0);

        // Check balances for the supplier
        (inP2PSupplier, onPoolSupplier) = morpho.supplyBalanceInOf(aDai, address(supplier1));

        uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);

        testEquality(inP2PSupplier, (suppliedAmount / 2).rayDiv(p2pBorrowIndex));
        testEquality(
            onPoolSupplier,
            (suppliedAmount / 2).rayDiv(pool.getReserveNormalizedIncome(dai))
        );

        // Now test for each individual borrower that replaced the original
        for (uint256 i; i < borrowers.length; i++) {
            if (borrowers[i] == borrower1) continue;

            (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrowers[i]));
            uint256 expectedInP2P = inP2P.rayMul(p2pBorrowIndex);

            testEquality(amountPerBorrower, expectedInP2P);
            testEquality(onPool, 0);
        }
    }

    struct Vars {
        uint256 LR;
        uint256 NI;
        uint256 APR;
        uint256 VBR;
        uint256 SP2PD;
        uint256 SP2PA;
        uint256 SP2PER;
    }

    function testDeltaRepay() public {
        // Allows only 10 unmatch borrowers
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 3e6, 0.8e6);

        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = 20 * suppliedAmount;
        uint256 collateral = 2 * borrowedAmount;
        uint256 expectedBorrowBalanceInP2P;

        // borrower1 and 100 suppliers are matched for borrowedAmount
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        createSigners(30);

        // 2 * NMAX suppliers supply suppliedAmount
        for (uint256 i; i < 20; i++) {
            suppliers[i].approve(dai, type(uint256).max);
            suppliers[i].supply(aDai, suppliedAmount - i); // Minus i to get the right ordering.
        }

        {
            uint256 p2pBorrowIndex = morpho.p2pBorrowIndex(aDai);
            expectedBorrowBalanceInP2P = borrowedAmount.rayDiv(p2pBorrowIndex);

            // Check balances after match of supplier1
            (uint256 inP2PBorrower, uint256 onPoolBorrower) = morpho.borrowBalanceInOf(
                aDai,
                address(borrower1)
            );
            assertApproxEqAbs(onPoolBorrower, 0, 1e3);
            assertApproxEqAbs(inP2PBorrower, expectedBorrowBalanceInP2P, 1e3);

            uint256 p2pSupplyIndex = morpho.p2pSupplyIndex(aDai);
            uint256 expectedSupplyBalanceInP2P = suppliedAmount.rayDiv(p2pSupplyIndex);

            for (uint256 i = 0; i < 20; i++) {
                (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
                    aDai,
                    address(suppliers[i])
                );
                testEquality(onPoolSupplier, 0);
                testEquality(inP2PSupplier, expectedSupplyBalanceInP2P);
            }

            // Borrower repays max
            // Should create a delta on suppliers side
            borrower1.approve(dai, type(uint256).max);
            borrower1.repay(aDai, type(uint256).max);

            // Check balances for borrower1
            (uint256 inP2PBorrower1, uint256 onPoolBorrower1) = morpho.supplyBalanceInOf(
                aDai,
                address(borrower1)
            );
            testEquality(onPoolBorrower1, 0);
            testEquality(inP2PBorrower1, 0);

            // There should be a delta
            uint256 expectedSupplyP2PDeltaInUnderlying = 10 * suppliedAmount;
            uint256 expectedSupplyP2PDelta = expectedSupplyP2PDeltaInUnderlying.rayDiv(
                pool.getReserveNormalizedIncome(dai)
            );
            (uint256 supplyP2PDelta, , , ) = morpho.deltas(aDai);
            assertApproxEqAbs(supplyP2PDelta, expectedSupplyP2PDelta, 1e3);

            // Supply delta matching by a new borrower
            borrower2.approve(usdc, to6Decimals(collateral));
            borrower2.supply(aUsdc, to6Decimals(collateral));
            borrower2.borrow(aDai, expectedSupplyP2PDeltaInUnderlying / 2);

            (inP2PBorrower, onPoolBorrower) = morpho.borrowBalanceInOf(aDai, address(borrower2));
            expectedBorrowBalanceInP2P = (expectedSupplyP2PDeltaInUnderlying / 2).rayDiv(
                p2pBorrowIndex
            );

            (supplyP2PDelta, , , ) = morpho.deltas(aDai);
            assertApproxEqAbs(
                supplyP2PDelta,
                expectedSupplyP2PDelta / 2,
                1e3,
                "supply delta unexpected"
            );
            testEquality(onPoolBorrower, 0, "on pool unexpected");
            testEquality(inP2PBorrower, expectedBorrowBalanceInP2P, "in peer-to-peer unexpected");
        }

        {
            Vars memory oldVars;
            Vars memory newVars;

            (oldVars.SP2PD, , oldVars.SP2PA, ) = morpho.deltas(aDai);
            oldVars.NI = pool.getReserveNormalizedIncome(dai);
            oldVars.SP2PER = morpho.p2pSupplyIndex(aDai);
            (oldVars.APR, ) = getApproxP2PRates(aDai);

            move1YearForward(aDai);

            (newVars.SP2PD, , newVars.SP2PA, ) = morpho.deltas(aDai);
            newVars.NI = pool.getReserveNormalizedIncome(dai);
            newVars.SP2PER = morpho.p2pSupplyIndex(aDai);
            newVars.LR = pool.getReserveData(dai).currentLiquidityRate;
            newVars.VBR = pool.getReserveData(dai).currentVariableBorrowRate;

            uint256 shareOfTheDelta = newVars
            .SP2PD
            .rayMul(newVars.NI)
            .rayDiv(oldVars.SP2PER)
            .rayDiv(newVars.SP2PA);

            uint256 expectedSP2PER = oldVars.SP2PER.rayMul(
                computeCompoundedInterest(oldVars.APR, 365 days).rayMul(
                    WadRayMath.RAY - shareOfTheDelta
                ) + shareOfTheDelta.rayMul(newVars.NI).rayDiv(oldVars.NI)
            );

            assertApproxEqAbs(
                expectedSP2PER,
                newVars.SP2PER,
                (expectedSP2PER * 2) / 100,
                "SP2PER not expected"
            );

            uint256 expectedSupplyBalanceInUnderlying = suppliedAmount
            .rayDiv(oldVars.SP2PER)
            .rayMul(expectedSP2PER);

            for (uint256 i = 10; i < 20; i++) {
                (uint256 inP2PSupplier, uint256 onPoolSupplier) = morpho.supplyBalanceInOf(
                    aDai,
                    address(suppliers[i])
                );
                assertApproxEqAbs(
                    inP2PSupplier.rayMul(newVars.SP2PER),
                    expectedSupplyBalanceInUnderlying,
                    (expectedSupplyBalanceInUnderlying * 2) / 100,
                    "not expected balance peer-to-peer"
                );
                testEquality(onPoolSupplier, 0, "not expected balance pool");
            }
        }

        // Supply delta reduction with suppliers withdrawing
        for (uint256 i = 10; i < 20; i++) {
            suppliers[i].withdraw(aDai, suppliedAmount);
        }

        (uint256 supplyP2PDeltaAfter, , , ) = morpho.deltas(aDai);
        testEquality(supplyP2PDeltaAfter, 0);

        (uint256 inP2PBorrower2, uint256 onPoolBorrower2) = morpho.borrowBalanceInOf(
            aDai,
            address(borrower2)
        );

        testEquality(inP2PBorrower2, expectedBorrowBalanceInP2P);
        testEquality(onPoolBorrower2, 0);
    }

    function testDeltaRepayAll() public {
        // Allows only 10 unmatch suppliers.
        setDefaultMaxGasForMatchingHelper(3e6, 3e6, 3e6, 0.8e6);

        uint256 suppliedAmount = 1 ether;
        uint256 borrowedAmount = 20 * suppliedAmount + 1e12;
        uint256 collateral = 2 * borrowedAmount;

        // borrower1 and 100 suppliers are matched for borrowedAmount.
        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, borrowedAmount);

        createSigners(30);

        // 2 * NMAX suppliers supply suppliedAmount.
        for (uint256 i = 0; i < 20; i++) {
            suppliers[i].approve(dai, suppliedAmount + i);
            suppliers[i].supply(aDai, suppliedAmount + i);
        }

        for (uint256 i = 0; i < 20; i++) {
            (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(suppliers[i]));
            assertEq(inP2P, (suppliedAmount + i).rayDiv(morpho.p2pSupplyIndex(aDai)), "inP2P");
            assertEq(onPool, 0, "onPool");
        }

        // Borrower repays max.
        // Should create a delta on suppliers side.
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);

        for (uint256 i = 10; i < 20; i++) {
            (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(suppliers[i]));
            assertEq(inP2P, 0, string.concat("inP2P", Strings.toString(i)));
            assertApproxEqAbs(
                onPool,
                (suppliedAmount + i).rayDiv(pool.getReserveNormalizedIncome(dai)),
                1e2,
                string.concat("onPool", Strings.toString(i))
            );
        }
        for (uint256 i = 0; i < 10; i++) {
            (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(suppliers[i]));
            assertApproxEqAbs(
                inP2P,
                (suppliedAmount + i).rayDiv(morpho.p2pSupplyIndex(aDai)),
                1e4,
                string.concat("inP2P", Strings.toString(i))
            );
            assertEq(onPool, 0, string.concat("onPool", Strings.toString(i)));
        }

        (
            uint256 p2pSupplyDelta,
            uint256 p2pBorrowDelta,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount
        ) = morpho.deltas(aDai);

        assertApproxEqAbs(
            p2pSupplyDelta,
            (10 * suppliedAmount).rayDiv(pool.getReserveNormalizedIncome(dai)),
            1e2,
            "p2pSupplyDelta"
        );
        assertEq(p2pBorrowDelta, 0, "p2pBorrowDelta");
        assertApproxEqAbs(
            p2pSupplyAmount,
            (10 * suppliedAmount).rayDiv(morpho.p2pSupplyIndex(aDai)),
            1e2,
            "p2pSupplyAmount"
        );
        assertApproxEqAbs(p2pBorrowAmount, 0, 1, "p2pBorrowAmount");

        hevm.warp(block.timestamp + (1 days));

        for (uint256 i; i < 20; i++) {
            suppliers[i].withdraw(aDai, type(uint256).max);
        }

        for (uint256 i = 0; i < 20; i++) {
            (uint256 inP2P, uint256 onPool) = morpho.supplyBalanceInOf(aDai, address(suppliers[i]));
            assertEq(inP2P, 0, "inP2P");
            assertEq(onPool, 0, "onPool");
        }
    }

    function testRepayZero() public {
        vm.expectRevert(abi.encodeWithSignature("AmountIsZero()"));
        morpho.repay(aDai, msg.sender, 0);
    }

    function testRepayRepayOnBehalf() public {
        uint256 amount = 1 ether;

        // Borrow on pool.
        borrower1.approve(usdc, to6Decimals(2 * amount));
        borrower1.supply(aUsdc, to6Decimals(2 * amount));
        borrower1.borrow(aDai, amount);

        // Someone repays on behalf of Morpho.
        supplier1.approve(dai, address(pool), amount);
        hevm.prank(address(supplier1));
        pool.repay(dai, amount, 2, address(morpho));

        // Repay max. Not supposed to revert !
        borrower1.approve(dai, type(uint256).max);
        borrower1.repay(aDai, type(uint256).max);
    }

    /// TODO: fix this test
    function __testUsdtAllowance() public {
        uint256 amount = to6Decimals(10 ether);

        borrower1.approve(usdc, 10 * amount);
        borrower1.supply(aUsdc, 10 * amount);
        // Borrow amount
        borrower1.borrow(aUsdt, amount);

        uint256 initialDebt = IVariableDebtToken(pool.getReserveData(usdt).variableDebtTokenAddress)
        .scaledBalanceOf(address(morpho));

        // Repay on-behalf of Morpho
        deal(usdt, address(this), amount / 2);
        ERC20(usdt).safeApprove(address(pool), amount / 2);
        pool.repay(usdt, amount / 2, 2, address(morpho));

        uint256 remainingDebt = IVariableDebtToken(
            pool.getReserveData(usdt).variableDebtTokenAddress
        ).scaledBalanceOf(address(morpho));

        assertLt(remainingDebt, initialDebt);

        // Borrower1 comes to repay all his debt ignoring the previous
        // Repay on Behalf of Positions Manager
        borrower1.approve(usdt, amount);
        borrower1.repay(aUsdt, amount);

        // Make sure that USDT's Position Manager allowance is set to 0
        assertEq(ERC20(usdt).allowance(address(morpho), address(pool)), 0);
    }

    function testRepayOnBehalf() public {
        uint256 amount = 10_000 ether;
        uint256 collateral = 2 * amount;

        borrower1.approve(usdc, to6Decimals(collateral));
        borrower1.supply(aUsdc, to6Decimals(collateral));
        borrower1.borrow(aDai, amount);

        borrower2.approve(dai, amount);
        hevm.prank(address(borrower2));
        morpho.repay(aDai, address(borrower1), amount);

        (uint256 inP2P, uint256 onPool) = morpho.borrowBalanceInOf(aDai, address(borrower1));

        assertEq(inP2P, 0);
        assertEq(onPool, 0);
    }

    function testRepayWithMaxP2PSupplyDelta() public {
        uint256 supplyAmount = 1_000 ether;
        uint256 borrowAmount = 50 ether;

        supplier1.approve(dai, type(uint256).max);
        supplier1.supply(aDai, supplyAmount);
        supplier1.borrow(aDai, borrowAmount);
        setDefaultMaxGasForMatchingHelper(0, 0, 0, 0);
        supplier1.withdraw(aDai, borrowAmount); // Creates a 100% peer-to-peer borrow delta.

        hevm.warp(block.timestamp + 1000);

        supplier1.repay(aDai, type(uint256).max);
    }
}
