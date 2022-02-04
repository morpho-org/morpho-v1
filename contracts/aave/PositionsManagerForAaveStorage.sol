// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.7;

import {IVariableDebtToken} from "./interfaces/aave/IVariableDebtToken.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/IMarketsManagerForAave.sol";
import "./interfaces/IMatchingEngineForAave.sol";
import "./interfaces/IRewardsManager.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../common/libraries/DoubleLinkedList.sol";
import "./libraries/aave/WadRayMath.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PositionsManagerForAaveStorage is ReentrancyGuard {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// Structs ///

    struct SupplyBalance {
        uint256 inP2P; // In supplier's p2pUnit, a unit that grows in value, to keep track of the interests earned when users are in P2P.
        uint256 onPool; // In aToken.
    }

    struct BorrowBalance {
        uint256 inP2P; // In borrower's p2pUnit, a unit that grows in value, to keep track of the interests paid when users are in P2P.
        uint256 onPool; // In adUnit, a unit that grows in value, to keep track of the debt increase when users are in Aave. Multiply by current borrowIndex to get the underlying amount.
    }

    /// Storage ///

    uint256 public constant MAX_BASIS_POINTS = 10000;
    uint16 public NMAX = 1000;
    uint8 public constant NO_REFERRAL_CODE = 0;
    uint8 public constant VARIABLE_INTEREST_MODE = 2;
    uint256 public constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000; // 50 % in basis points.
    bytes32 public constant DATA_PROVIDER_ID =
        0x1000000000000000000000000000000000000000000000000000000000000000; // Id of the data provider.
    mapping(address => DoubleLinkedList.List) internal suppliersInP2P; // Suppliers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal suppliersOnPool; // Suppliers on Aave.
    mapping(address => DoubleLinkedList.List) internal borrowersInP2P; // Borrowers in peer-to-peer.
    mapping(address => DoubleLinkedList.List) internal borrowersOnPool; // Borrowers on Aave.
    mapping(address => mapping(address => SupplyBalance)) public supplyBalanceInOf; // For a given market, the supply balance of a user.
    mapping(address => mapping(address => BorrowBalance)) public borrowBalanceInOf; // For a given market, the borrow balance of a user.
    mapping(address => mapping(address => bool)) public userMembership; // Whether the user is in the market or not.
    mapping(address => address[]) public enteredMarkets; // The markets entered by a user.
    mapping(address => uint256) public threshold; // Thresholds below the ones suppliers and borrowers cannot enter markets.

    IAaveIncentivesController public aaveIncentivesController;
    IRewardsManager public rewardsManager;
    ILendingPoolAddressesProvider public addressesProvider;
    ILendingPool public lendingPool;
    IProtocolDataProvider public dataProvider;
    IMarketsManagerForAave public marketsManager;
    IMatchingEngineForAave public matchingEngine;
    address public treasuryVault;

    /// Internal ///

    /// @dev Supplies undelrying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to supply to.
    /// @param _amount The amount of token (in underlying).
    function _supplyERC20ToPool(IERC20 _underlyingToken, uint256 _amount) public {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        lendingPool.deposit(address(_underlyingToken), _amount, address(this), NO_REFERRAL_CODE);
    }

    /// @dev Withdraws underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to withdraw from.
    /// @param _amount The amount of token (in underlying).
    function _withdrawERC20FromPool(IERC20 _underlyingToken, uint256 _amount) public {
        lendingPool.withdraw(address(_underlyingToken), _amount, address(this));
    }

    /// @dev Borrows underlying tokens from Aave.
    /// @param _underlyingToken The underlying token of the market to borrow from.
    /// @param _amount The amount of token (in underlying).
    function _borrowERC20FromPool(IERC20 _underlyingToken, uint256 _amount) public {
        lendingPool.borrow(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            NO_REFERRAL_CODE,
            address(this)
        );
    }

    /// @dev Repays underlying tokens to Aave.
    /// @param _underlyingToken The underlying token of the market to repay to.
    /// @param _amount The amount of token (in underlying).
    /// @param _normalizedVariableDebt The normalized variable debt on Aave.
    function _repayERC20ToPool(
        IERC20 _underlyingToken,
        uint256 _amount,
        uint256 _normalizedVariableDebt
    ) public {
        _underlyingToken.safeIncreaseAllowance(address(lendingPool), _amount);
        (, , address variableDebtToken) = dataProvider.getReserveTokensAddresses(
            address(_underlyingToken)
        );
        // Do not repay more than the contract's debt on Aave
        _amount = Math.min(
            _amount,
            IVariableDebtToken(variableDebtToken).scaledBalanceOf(address(this)).mulWadByRay(
                _normalizedVariableDebt
            )
        );
        lendingPool.repay(
            address(_underlyingToken),
            _amount,
            VARIABLE_INTEREST_MODE,
            address(this)
        );
    }
}
