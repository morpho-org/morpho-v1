// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "./IEntryPositionsManager.sol";
import "./IExitPositionsManager.sol";
import "./IInterestRatesManager.sol";
import "./IIncentivesVault.sol";
import "./IRewardsManager.sol";

import "../libraries/Types.sol";

// prettier-ignore
interface IMorpho {

    /// STORAGE ///

    function isClaimRewardsPaused() external view returns (bool);
    function defaultMaxGasForMatching() external view returns (Types.MaxGasForMatching memory);
    function maxSortedUsers() external view returns (uint256);
    function supplyBalanceInOf(address, address) external view returns (Types.SupplyBalance memory);
    function borrowBalanceInOf(address, address) external view returns (Types.BorrowBalance memory);
    function deltas(address) external view returns (Types.Delta memory);
    function marketsCreated() external view returns (address[] memory);
    function marketInfos(address) external view returns (Types.MarketInfos memory);
    function p2pDisabled(address) external view returns (bool);
    function p2pSupplyIndex(address) external view returns (uint256);
    function p2pBorrowIndex(address) external view returns (uint256);
    function poolIndexes(address) external view returns (Types.PoolIndexes memory);
    function marketStatus(address) external view returns (Types.MarketStatus memory);
    function interestRatesManager() external view returns (IInterestRatesManager);
    function rewardsManager() external view returns (IRewardsManager);
    function entryPositionsManager() external view returns (IEntryPositionsManager);
    function exitPositionsManager() external view returns (IExitPositionsManager);
    function rewardsController() external view returns (IRewardsController);
    function addressesProvider() external view returns (IPoolAddressesProvider);
    function incentivesVault() external view returns (IIncentivesVault);
    function pool() external view returns (IPool);
    function treasuryVault() external view returns (address);
    function borrowMask(address) external view returns (bytes32);
    function userMarkets(address) external view returns (bytes32);

    /// UTILS ///

    function updateIndexes(address _poolTokenAddress) external;

    /// GETTERS ///

    function getMarketsCreated() external view returns (address[] memory marketsCreated_);
    function getHead(address _poolTokenAddress, Types.PositionType _positionType) external view returns (address head);
    function getNext(address _poolTokenAddress, Types.PositionType _positionType, address _user) external view returns (address next);

    /// GOVERNANCE ///

    function setMaxSortedUsers(uint256 _newMaxSortedUsers) external;
    function setDefaultMaxGasForMatching(Types.MaxGasForMatching memory _maxGasForMatching) external;
    function setTreasuryVault(address _newTreasuryVaultAddress) external;
    function setIncentivesVault(address _newIncentivesVault) external;
    function setRewardsManager(address _rewardsManagerAddress) external;
    function setPauseStatus(address _poolTokenAddress, bool _p2pDisabled) external;
    function setP2PDisabled(address _poolTokenAddress, bool _p2pDisabled) external;
    function setReserveFactor(address _poolTokenAddress, uint256 _newReserveFactor) external;
    function setP2PIndexCursor(address _poolTokenAddress, uint16 _p2pIndexCursor) external;
    function setPauseStatus(address _poolTokenAddress) external;
    function setPartialPauseStatus(address _poolTokenAddress) external;
    function setExitPositionsManager(IExitPositionsManager _exitPositionsManager) external;
    function setEntryPositionsManager(IEntryPositionsManager _entryPositionsManager)
        external;
    function setInterestRatesManager(IInterestRatesManager _interestRatesManager) external;
    function claimToTreasury(address[] calldata _poolTokenAddresses, uint256[] calldata _amounts) external;
    function createMarket(address _poolTokenAddress, Types.MarketInfos calldata _marketInfos) external;

    /// USERS ///

    function supply(address _poolTokenAddress, address _onBehalf, uint256 _amount) external;
    function supply(address _poolTokenAddress, address _onBehalf, uint256 _amount, uint256 _maxGasForMatching) external;
    function borrow(address _poolTokenAddress, uint256 _amount) external;
    function borrow(address _poolTokenAddress, uint256 _amount, uint256 _maxGasForMatching) external;
    function withdraw(address _poolTokenAddress, uint256 _amount) external;
    function repay(address _poolTokenAddress, address _onBehalf, uint256 _amount) external;
    function liquidate(address _poolTokenBorrowedAddress, address _poolTokenCollateralAddress, address _borrower, uint256 _amount) external;
    function claimRewards(address[] calldata _cTokenAddresses, bool _tradeForMorphoToken) external returns (address[] memory rewardTokens, uint256[] memory claimedAmounts);
}
