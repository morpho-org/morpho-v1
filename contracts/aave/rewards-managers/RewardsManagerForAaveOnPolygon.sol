// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "../RewardsManager.sol";

contract RewardsManagerForAaveOnPolygon is RewardsManager {
    constructor(
        ILendingPool _lendingPool,
        IMorpho _morpho,
        address _swapManager
    ) RewardsManager(_lendingPool, _morpho, _swapManager) {}

    /// @inheritdoc RewardsManager
    function _getUpdatedIndex(address _asset, uint256 _totalBalance)
        internal
        override
        returns (uint256 newIndex)
    {
        LocalAssetData storage localData = localAssetData[_asset];
        uint256 blockTimestamp = block.timestamp;
        uint256 lastTimestamp = localData.lastUpdateTimestamp;

        if (blockTimestamp == lastTimestamp) return localData.lastIndex;
        else {
            IAaveIncentivesController.AssetData memory assetData = aaveIncentivesController.assets(
                _asset
            );
            uint256 oldIndex = assetData.index;
            uint128 lastTimestampOnAave = assetData.lastUpdateTimestamp;

            newIndex = _getAssetIndex(
                oldIndex,
                assetData.emissionPerSecond,
                lastTimestampOnAave,
                _totalBalance
            );
            localData.lastUpdateTimestamp = blockTimestamp;
            localData.lastIndex = newIndex;
        }
    }

    /// @inheritdoc RewardsManager
    function _getNewIndex(address _asset, uint256 _totalBalance)
        internal
        view
        override
        returns (uint256 newIndex)
    {
        LocalAssetData storage localData = localAssetData[_asset];
        uint256 blockTimestamp = block.timestamp;
        uint256 lastTimestamp = localData.lastUpdateTimestamp;

        if (blockTimestamp == lastTimestamp) return localData.lastIndex;
        else {
            IAaveIncentivesController.AssetData memory assetData = aaveIncentivesController.assets(
                _asset
            );
            uint256 oldIndex = assetData.index;
            uint128 lastTimestampOnAave = assetData.lastUpdateTimestamp;

            newIndex = _getAssetIndex(
                oldIndex,
                assetData.emissionPerSecond,
                lastTimestampOnAave,
                _totalBalance
            );
        }
    }
}