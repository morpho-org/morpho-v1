// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/DataTypes.sol";
import {IAToken} from "./interfaces/aave/IAToken.sol";
import "./interfaces/IPositionsManagerForAave.sol";
import "./interfaces/IMarketsManagerForAave.sol";

import "./libraries/aave/WadRayMath.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MarketsManagerForAave
/// @dev Smart contract managing the markets used by a MorphoPositionsManagerForAave contract, an other contract interacting with Aave or a fork of Aave.
contract MarketsManagerForAave is Ownable {
    using WadRayMath for uint256;
    using Math for uint256;

    /// Storage ///

    uint256 public constant MAX_BASIS_POINTS = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public feeFactor; // Proportion of the spread that is taken as a protocol fee, in basis point (default is no fee).

    mapping(address => bool) public isCreated; // Whether or not this market is created.
    mapping(address => uint256) public supplyP2PSPY; // Supply Second Percentage Yield, in ray.
    mapping(address => uint256) public borrowP2PSPY; // Borrow Second Percentage Yield, in ray.
    mapping(address => uint256) public supplyP2PExchangeRate; // Current exchange rate from supply p2pUnit to underlying.
    mapping(address => uint256) public borrowP2PExchangeRate; // Current exchange rate from borrow p2pUnit to underlying.
    mapping(address => uint256) public exchangeRatesLastUpdateTimestamp; // Last time p2pExchangeRates were updated.

    IPositionsManagerForAave public positionsManagerForAave;
    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public lendingPool;

    /// Events ///

    /// @dev Emitted when a new market is created.
    /// @param _marketAddress The address of the market that has been created.
    event MarketCreated(address _marketAddress);

    /// @dev Emitted when the lendingPool is set on the `positionsManagerForAave`.
    /// @param _lendingPoolAddress The address of the lending pool.
    event LendingPoolSet(address _lendingPoolAddress);

    /// @dev Emitted when the `positionsManagerForAave` is set.
    /// @param _positionsManagerForAave The address of the `positionsManagerForAave`.
    event PositionsManagerForAaveSet(address _positionsManagerForAave);

    /// @dev Emitted when the P2P SPYs of a market are updated.
    /// @param _marketAddress The address of the market to update.
    /// @param _newSupplyP2PSPY The new value of the supply  P2P SPY.
    /// @param _newBorrowP2PSPY The new value of the borrow P2P SPY.
    event P2PSPYsUpdated(
        address _marketAddress,
        uint256 _newSupplyP2PSPY,
        uint256 _newBorrowP2PSPY
    );

    /// @dev Emitted when the p2pExchangeRate of a market is updated.
    /// @param _marketAddress The address of the market to update.
    /// @param _newSupplyP2PExchangeRate The new value of the supply exchange rate from p2pUnit to underlying.
    /// @param _newBorrowP2PExchangeRate The new value of the borrow exchange rate from p2pUnit to underlying.
    event P2PExchangeRatesUpdated(
        address _marketAddress,
        uint256 _newSupplyP2PExchangeRate,
        uint256 _newBorrowP2PExchangeRate
    );

    /// @dev Emitted when a threshold of a market is updated.
    /// @param _marketAddress The address of the market to update.
    /// @param _newValue The new value of the threshold.
    event ThresholdUpdated(address _marketAddress, uint256 _newValue);

    /// @dev Emitted when a cap value of a market is updated.
    /// @param _marketAddress The address of the market to update.
    /// @param _newValue The new value of the cap.
    event CapValueUpdated(address _marketAddress, uint256 _newValue);

    /// @dev Emitted the maximum number of users to have in the tree is updated.
    /// @param _newValue The new value of the maximum number of users to have in the tree.
    event MaxNumberUpdated(uint16 _newValue);

    /// Errors ///

    /// @notice Emitted when the market is not created yet.
    error MarketNotCreated();

    /// @notice Emitted when the market is already created.
    error MarketAlreadyCreated();

    /// @notice Emitted when the positionsManager is already set.
    error PositionsManagerAlreadySet();

    /// Modifiers ///

    /// @dev Prevents to update a market not created yet.
    modifier isMarketCreated(address _marketAddress) {
        if (!isCreated[_marketAddress]) revert MarketNotCreated();
        _;
    }

    /// Constructor ///

    /// @dev Constructs the MarketsManagerForAave contract.
    /// @param _lendingPoolAddressesProvider The address of the lending pool addresses provider.
    constructor(address _lendingPoolAddressesProvider) {
        addressesProvider = ILendingPoolAddressesProvider(_lendingPoolAddressesProvider);
    }

    /// External ///

    /// @dev Sets the `positionsManagerForAave` to interact with Aave.
    /// @param _positionsManagerForAave The address of compound module.
    function setPositionsManager(address _positionsManagerForAave) external onlyOwner {
        if (address(positionsManagerForAave) != address(0)) revert PositionsManagerAlreadySet();
        positionsManagerForAave = IPositionsManagerForAave(_positionsManagerForAave);
        emit PositionsManagerForAaveSet(_positionsManagerForAave);
    }

    /// @dev Updates the lending pool.
    function updateLendingPool() external onlyOwner {
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
        emit LendingPoolSet(address(lendingPool));
    }

    /// @dev Sets the maximum number of users in tree.
    /// @param _newMaxNumber The maximum number of users to have in the tree.
    function setNmaxForMatchingEngine(uint16 _newMaxNumber) external onlyOwner {
        positionsManagerForAave.setNmaxForMatchingEngine(_newMaxNumber);
        emit MaxNumberUpdated(_newMaxNumber);
    }

    /// @dev Sets the protocol fee.
    /// @param _newFeeFactor Factor of the spread that is taken as a protocol fee, in basis points.
    function setFee(uint256 _newFeeFactor) external onlyOwner {
        feeFactor = Math.min(MAX_BASIS_POINTS, _newFeeFactor);
    }

    /// @dev Creates a new market to borrow/supply.
    /// @param _marketAddress The addresses of the markets to add (aToken).
    /// @param _threshold The threshold to set for the market.
    /// @param _capValue The cap value to set for the market.
    function createMarket(
        address _marketAddress,
        uint256 _threshold,
        uint256 _capValue
    ) external onlyOwner {
        if (isCreated[_marketAddress]) revert MarketAlreadyCreated();

        positionsManagerForAave.setThreshold(_marketAddress, _threshold);
        positionsManagerForAave.setCapValue(_marketAddress, _capValue);

        exchangeRatesLastUpdateTimestamp[_marketAddress] = block.timestamp;
        supplyP2PExchangeRate[_marketAddress] = WadRayMath.ray();
        borrowP2PExchangeRate[_marketAddress] = WadRayMath.ray();
        isCreated[_marketAddress] = true;

        _updateSPYs(_marketAddress);
        emit MarketCreated(_marketAddress);
    }

    /// @dev Updates the threshold below which suppliers and borrowers cannot join a given market.
    /// @param _marketAddress The address of the market to change the threshold.
    /// @param _newThreshold The new threshold to set.
    function updateThreshold(address _marketAddress, uint256 _newThreshold)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        positionsManagerForAave.setThreshold(_marketAddress, _newThreshold);
        emit ThresholdUpdated(_marketAddress, _newThreshold);
    }

    /// @dev Updates the cap value above which suppliers cannot supply more tokens.
    /// @param _marketAddress The address of the market to change the max cap.
    /// @param _newCapValue The new max cap to set.
    function updateCapValue(address _marketAddress, uint256 _newCapValue)
        external
        onlyOwner
        isMarketCreated(_marketAddress)
    {
        positionsManagerForAave.setCapValue(_marketAddress, _newCapValue);
        emit CapValueUpdated(_marketAddress, _newCapValue);
    }

    /// Public ///

    /// @dev Updates the P2P Second Percentage Yield and calculates the current P2P exchange rates.
    /// @param _marketAddress The address of the market we want to update.
    function updateRates(address _marketAddress) public isMarketCreated(_marketAddress) {
        if (exchangeRatesLastUpdateTimestamp[_marketAddress] != block.timestamp) {
            _updateP2PExchangeRates(_marketAddress);
            _updateSPYs(_marketAddress);
        }
    }

    /// Internal ///

    /// @dev Updates the P2P exchange rate, taking into account the Second Percentage Yield (`p2pSPY`) since the last time it has been updated.
    /// @param _marketAddress The address of the market to update.
    function _updateP2PExchangeRates(address _marketAddress) internal {
        uint256 timeDifference = block.timestamp - exchangeRatesLastUpdateTimestamp[_marketAddress];
        exchangeRatesLastUpdateTimestamp[_marketAddress] = block.timestamp;

        uint256 newSupplyP2PExchangeRate = supplyP2PExchangeRate[_marketAddress].rayMul(
            (WadRayMath.ray() + supplyP2PSPY[_marketAddress]).rayPow(timeDifference)
        ); // In ray
        supplyP2PExchangeRate[_marketAddress] = newSupplyP2PExchangeRate;

        uint256 newBorrowP2PExchangeRate = borrowP2PExchangeRate[_marketAddress].rayMul(
            (WadRayMath.ray() + borrowP2PSPY[_marketAddress]).rayPow(timeDifference)
        ); // In ray
        borrowP2PExchangeRate[_marketAddress] = newBorrowP2PExchangeRate;

        emit P2PExchangeRatesUpdated(
            _marketAddress,
            newSupplyP2PExchangeRate,
            newBorrowP2PExchangeRate
        );
    }

    /// @dev Updates the P2P Second Percentage Yield of supply and borrow.
    /// @param _marketAddress The address of the market to update.
    function _updateSPYs(address _marketAddress) internal {
        DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
            IAToken(_marketAddress).UNDERLYING_ASSET_ADDRESS()
        );

        uint256 meanSPY = Math.average(
            reserveData.currentLiquidityRate,
            reserveData.currentVariableBorrowRate
        ) / SECONDS_PER_YEAR; // In ray

        supplyP2PSPY[_marketAddress] =
            (meanSPY * (MAX_BASIS_POINTS - feeFactor)) /
            MAX_BASIS_POINTS;
        borrowP2PSPY[_marketAddress] =
            (meanSPY * (MAX_BASIS_POINTS + feeFactor)) /
            MAX_BASIS_POINTS;

        emit P2PSPYsUpdated(
            _marketAddress,
            supplyP2PSPY[_marketAddress],
            borrowP2PSPY[_marketAddress]
        );
    }
}
