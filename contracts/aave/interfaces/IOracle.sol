// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

interface IOracle {
    function consult(uint256 _amountIn) external returns (uint256);
}
