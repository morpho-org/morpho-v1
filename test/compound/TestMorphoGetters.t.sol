// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./setup/TestSetup.sol";

contract TestMorphoGetters is TestSetup {
    using CompoundMath for uint256;

    struct UserBalanceStates {
        uint256 collateralValue;
        uint256 debtValue;
        uint256 maxDebtValue;
        uint256 liquidationValue;
    }

    enum PositionType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    function testGetHead() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = amount / 10;

        borrower1.approve(dai, amount);
        borrower1.supply(cDai, amount);

        assertEq(address(0), morpho.getHead(cDai, Types.PositionType.SUPPLIERS_IN_P2P));
        assertEq(address(borrower1), morpho.getHead(cDai, Types.PositionType.SUPPLIERS_ON_POOL));
        assertEq(address(0), morpho.getHead(cDai, Types.PositionType.BORROWERS_IN_P2P));
        assertEq(address(0), morpho.getHead(cDai, Types.PositionType.BORROWERS_ON_POOL));

        borrower1.borrow(cDai, toBorrow);

        assertEq(address(borrower1), morpho.getHead(cDai, Types.PositionType.SUPPLIERS_IN_P2P));
        assertEq(address(borrower1), morpho.getHead(cDai, Types.PositionType.SUPPLIERS_ON_POOL));
        assertEq(address(borrower1), morpho.getHead(cDai, Types.PositionType.BORROWERS_IN_P2P));
        assertEq(address(0), morpho.getHead(cDai, Types.PositionType.BORROWERS_ON_POOL));

        borrower1.borrow(cUsdc, to6Decimals(toBorrow));

        assertEq(address(borrower1), morpho.getHead(cUsdc, Types.PositionType.BORROWERS_ON_POOL));
    }

    function testGetNext() public {
        uint256 amount = 10_000 ether;
        uint256 toBorrow = amount / 10;

        uint256 maxSortedUsers = 10;
        morpho.setMaxSortedUsers(maxSortedUsers);
        createSigners(maxSortedUsers);
        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].approve(dai, amount - i * 1e18);
            borrowers[i].supply(cDai, amount - i * 1e18);
            borrowers[i].borrow(cUsdc, to6Decimals(toBorrow - i * 1e18));
        }

        address nextSupplyOnPool = address(borrowers[0]);
        address nextBorrowOnPool = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyOnPool = morpho.getNext(
                cDai,
                Types.PositionType.SUPPLIERS_ON_POOL,
                nextSupplyOnPool
            );
            nextBorrowOnPool = morpho.getNext(
                cUsdc,
                Types.PositionType.BORROWERS_ON_POOL,
                nextBorrowOnPool
            );

            assertEq(nextSupplyOnPool, address(borrowers[i + 1]));
            assertEq(nextBorrowOnPool, address(borrowers[i + 1]));
        }

        for (uint256 i; i < borrowers.length; i++) {
            borrowers[i].borrow(cDai, (amount / 100) - i * 1e18);
        }

        for (uint256 i; i < suppliers.length; i++) {
            suppliers[i].approve(usdc, to6Decimals(toBorrow - i * 1e18));
            suppliers[i].supply(cUsdc, to6Decimals(toBorrow - i * 1e18));
        }

        address nextSupplyInP2P = address(suppliers[0]);
        address nextBorrowInP2P = address(borrowers[0]);

        for (uint256 i; i < borrowers.length - 1; i++) {
            nextSupplyInP2P = morpho.getNext(
                cUsdc,
                Types.PositionType.SUPPLIERS_IN_P2P,
                nextSupplyInP2P
            );
            nextBorrowInP2P = morpho.getNext(
                cDai,
                Types.PositionType.BORROWERS_IN_P2P,
                nextBorrowInP2P
            );

            assertEq(address(suppliers[i + 1]), nextSupplyInP2P);
            assertEq(address(borrowers[i + 1]), nextBorrowInP2P);
        }
    }

    function testEnteredMarkets() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(cDai, 10 ether);

        borrower1.approve(usdc, to6Decimals(10 ether));
        borrower1.supply(cUsdc, to6Decimals(10 ether));

        assertEq(morpho.enteredMarkets(address(borrower1), 0), cDai);
        assertEq(IMorpho(address(morpho)).enteredMarkets(address(borrower1), 0), cDai); // test the interface
        assertEq(morpho.enteredMarkets(address(borrower1), 1), cUsdc);

        // Borrower1 withdraw, USDC should be the first in enteredMarkets.
        borrower1.withdraw(cDai, type(uint256).max);

        assertEq(morpho.enteredMarkets(address(borrower1), 0), cUsdc);
    }

    function testUserLeftMarkets() public {
        borrower1.approve(dai, 10 ether);
        borrower1.supply(cDai, 10 ether);

        // Check that borrower1 entered Dai market.
        assertEq(morpho.enteredMarkets(address(borrower1), 0), cDai);

        // Borrower1 withdraw everything from the Dai market.
        borrower1.withdraw(cDai, 10 ether);

        // Test should fail because there is no element in the array.
        vm.expectRevert();
        morpho.enteredMarkets(address(borrower1), 0);
    }

    function testGetAllMarkets() public {
        address[] memory marketsCreated = morpho.getAllMarkets();
        for (uint256 i; i < pools.length; i++) {
            assertEq(marketsCreated[i], pools[i]);
        }
    }
}
