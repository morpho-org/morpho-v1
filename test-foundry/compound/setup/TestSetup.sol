// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "@contracts/compound/interfaces/IRewardsManagerForCompound.sol";
import "@contracts/compound/interfaces/compound/ICompound.sol";
import "@contracts/compound/interfaces/IMorphoCompound.sol";
import "@contracts/common/interfaces/ISwapManager.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@contracts/compound/PositionsManagerForCompound.sol";
import "@contracts/compound/PositionsManagerForCompoundSettersAndGetters.sol";
import "@contracts/compound/MarketsManagerForCompound.sol";
import "@contracts/compound/RewardsManagerForCompound.sol";
import "@contracts/compound/MorphoLensForCompound.sol";
import "@contracts/compound/InitDiamond.sol";

import "@contracts/compound/libraries/FixedPointMathLib.sol";
import "@contracts/compound/libraries/Types.sol";

import "@contracts/common/diamond/Diamond.sol";
import "@contracts/common/diamond/facets/DiamondCutFacet.sol";
import "@contracts/common/diamond/facets/DiamondLoupeFacet.sol";
import "@contracts/common/diamond/facets/OwnershipFacet.sol";
import "@contracts/common/diamond/interfaces/IDiamondCut.sol";

import "../../common/helpers/MorphoToken.sol";
import "../../common/helpers/Chains.sol";
import "../helpers/SimplePriceOracle.sol";
import "../helpers/IncentivesVault.sol";
import "../helpers/DumbOracle.sol";
import {User} from "../helpers/User.sol";
import {Utils} from "./Utils.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "@config/Config.sol";

interface IAdminComptroller {
    function _setPriceOracle(SimplePriceOracle newOracle) external returns (uint256);

    function admin() external view returns (address);
}

contract TestSetup is Config, Utils, stdCheats {
    Vm public hevm = Vm(HEVM_ADDRESS);

    uint256 public constant MAX_BASIS_POINTS = 10_000;
    uint256 public constant INITIAL_BALANCE = 1_000_000;

    Diamond public diamond;
    DiamondCutFacet public diamondCutFacet;
    DiamondLoupeFacet public diamondLoupeFacet;
    OwnershipFacet public ownershipFacet;

    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public positionsManagerProxy;
    TransparentUpgradeableProxy public marketsManagerProxy;
    PositionsManagerForCompound internal positionsManagerImplV1;
    PositionsManagerForCompound internal positionsManager;
    PositionsManagerForCompound internal positionsManagerFacet;
    PositionsManagerForCompound internal fakePositionsManagerImpl;
    PositionsManagerForCompoundSettersAndGetters internal positionsManagerSettersAndGettersFacet;
    PositionsManagerForCompoundSettersAndGetters internal positionsManagerSettersAndGetters;
    MarketsManagerForCompound internal marketsManager;
    MarketsManagerForCompound internal marketsManagerImplV1;
    MarketsManagerForCompound internal marketsManagerFacet;
    IRewardsManagerForCompound internal rewardsManager;
    MorphoLensForCompound internal morphoLensFacet;
    MorphoLensForCompound internal morphoLens;

    IMorphoCompound internal morphoCompound;

    IncentivesVault public incentivesVault;
    DumbOracle internal dumbOracle;
    MorphoToken public morphoToken;
    IComptroller public comptroller;
    ICompoundOracle public oracle;

    User public supplier1;
    User public supplier2;
    User public supplier3;
    User[] public suppliers;
    User public borrower1;
    User public borrower2;
    User public borrower3;
    User[] public borrowers;
    User public treasuryVault;

    IDiamondCut.FacetCut[] private cuts;

    address[] public pools;

    function setUp() public {
        initContracts();
        setContractsLabels();
        initUsers();
    }

    function initContracts() internal {
        Types.MaxGas memory maxGas = Types.MaxGas({
            supply: 3e6,
            borrow: 3e6,
            withdraw: 3e6,
            repay: 3e6
        });

        comptroller = IComptroller(comptrollerAddress);

        /// Diamond ///
        diamondCutFacet = new DiamondCutFacet();
        diamondLoupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();

        diamond = new Diamond(address(this), address(diamondCutFacet));
        diamondCutFacet = DiamondCutFacet(address(diamond));
        marketsManagerFacet = new MarketsManagerForCompound();
        positionsManagerFacet = new PositionsManagerForCompound();
        positionsManagerSettersAndGettersFacet = new PositionsManagerForCompoundSettersAndGetters();
        morphoLensFacet = new MorphoLensForCompound();
        InitDiamond initDiamond = new InitDiamond();

        {
            bytes4[] memory marketsManagerFunctionSelectors = new bytes4[](18);
            {
                uint256 index;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .setReserveFactor
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .createMarket
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet.setNoP2P.selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .getAllMarkets
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .getMarketData
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .getMarketConfiguration
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .getUpdatedP2PExchangeRates
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .getUpdatedSupplyP2PExchangeRate
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .getUpdatedBorrowP2PExchangeRate
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .updateP2PExchangeRates
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet.isCreated.selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .reserveFactor
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .supplyP2PExchangeRate
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .borrowP2PExchangeRate
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .lastPoolIndexes
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet
                .lastUpdateBlockNumber
                .selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet.noP2P.selector;
                marketsManagerFunctionSelectors[index++] = marketsManagerFacet.comptroller.selector;
            }

            IDiamondCut.FacetCut memory marketsCut = IDiamondCut.FacetCut({
                facetAddress: address(marketsManagerFacet),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: marketsManagerFunctionSelectors
            });

            bytes4[] memory positionsManagerFunctionSelectors = new bytes4[](7);
            {
                uint256 index;
                positionsManagerFunctionSelectors[index++] = bytes4(
                    keccak256("supply(address,uint256)")
                );
                positionsManagerFunctionSelectors[index++] = bytes4(
                    keccak256("supply(address,uint256,uint256)")
                );
                positionsManagerFunctionSelectors[index++] = bytes4(
                    keccak256("borrow(address,uint256)")
                );
                positionsManagerFunctionSelectors[index++] = bytes4(
                    keccak256("borrow(address,uint256,uint256)")
                );
                positionsManagerFunctionSelectors[index++] = bytes4(
                    keccak256("withdraw(address,uint256)")
                );
                positionsManagerFunctionSelectors[index++] = bytes4(
                    keccak256("repay(address,uint256)")
                );
                positionsManagerFunctionSelectors[index++] = positionsManagerFacet
                .liquidate
                .selector;
            }

            IDiamondCut.FacetCut memory positionsCut = IDiamondCut.FacetCut({
                facetAddress: address(positionsManagerFacet),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: positionsManagerFunctionSelectors
            });

            bytes4[] memory positionsManagerSettersAndGettersFunctionSelectors = new bytes4[](11);
            {
                uint256 index;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.claimToTreasury.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.claimRewards.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.supplyBalanceInOf.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.borrowBalanceInOf.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.setNDS.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.setMaxGas.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.setTreasuryVault.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.setIncentivesVault.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.setRewardsManager.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.toggleCompRewardsActivation.selector;
                positionsManagerSettersAndGettersFunctionSelectors[
                    index++
                ] = positionsManagerSettersAndGettersFacet.setPauseStatus.selector;
            }

            IDiamondCut.FacetCut memory positionsSettersAndGettersCut = IDiamondCut.FacetCut({
                facetAddress: address(positionsManagerSettersAndGettersFacet),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: positionsManagerSettersAndGettersFunctionSelectors
            });

            bytes4[] memory morphoLensFunctionSelectors = new bytes4[](13);
            {
                uint256 index;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.deltas.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.rewardsManager.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.treasuryVault.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.isCompRewardsActive.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.paused.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.NDS.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.maxGas.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.getHead.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.getNext.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet.enteredMarkets.selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet
                .getUserBalanceStates
                .selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet
                .getUserLiquidityDataForAsset
                .selector;
                morphoLensFunctionSelectors[index++] = morphoLensFacet
                .getUserMaxCapacitiesForAsset
                .selector;
            }

            IDiamondCut.FacetCut memory lensCut = IDiamondCut.FacetCut({
                facetAddress: address(morphoLensFacet),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: morphoLensFunctionSelectors
            });

            cuts.push(marketsCut);
            cuts.push(positionsCut);
            cuts.push(positionsSettersAndGettersCut);
            cuts.push(lensCut);
        }
        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            address(initDiamond),
            abi.encodeWithSelector(
                initDiamond.init.selector,
                InitDiamond.Args({
                    comptroller: IComptroller(address(comptroller)),
                    maxGas: maxGas,
                    NDS: 20,
                    cEth: cEth,
                    wEth: wEth
                })
            )
        );

        positionsManager = PositionsManagerForCompound(payable(address(diamond)));
        positionsManagerSettersAndGetters = PositionsManagerForCompoundSettersAndGetters(
            address(diamond)
        );
        marketsManager = MarketsManagerForCompound(address(diamond));
        morphoLens = MorphoLensForCompound(address(diamond));
        morphoCompound = IMorphoCompound(address(diamond));

        treasuryVault = new User(address(diamond));
        fakePositionsManagerImpl = new PositionsManagerForCompound();
        oracle = ICompoundOracle(comptroller.oracle());
        morphoCompound.setTreasuryVault(address(treasuryVault));

        /// Create markets ///

        createMarket(cDai);
        createMarket(cUsdc);
        createMarket(cWbtc);
        createMarket(cUsdt);
        createMarket(cBat);
        createMarket(cEth);

        hevm.roll(block.number + 1);

        /// Create Morpho token, deploy Incentives Vault and activate COMP rewards ///

        morphoToken = new MorphoToken(address(this));
        dumbOracle = new DumbOracle();
        incentivesVault = new IncentivesVault(
            address(positionsManager),
            address(morphoToken),
            address(dumbOracle)
        );
        morphoToken.transfer(address(incentivesVault), 1_000_000 ether);

        rewardsManager = new RewardsManagerForCompound(address(positionsManager));

        morphoCompound.setRewardsManager(address(rewardsManager));
        morphoCompound.setIncentivesVault(address(incentivesVault));
        morphoCompound.toggleCompRewardsActivation();
    }

    function createMarket(address _cToken) internal {
        marketsManager.createMarket(_cToken);

        // All tokens must also be added to the pools array, for the correct behavior of TestLiquidate::createAndSetCustomPriceOracle.
        pools.push(_cToken);

        hevm.label(_cToken, ERC20(_cToken).symbol());
        if (_cToken == cEth) hevm.label(wEth, "WETH");
        else {
            address underlying = ICToken(_cToken).underlying();
            hevm.label(underlying, ERC20(underlying).symbol());
        }
    }

    function initUsers() internal {
        for (uint256 i = 0; i < 3; i++) {
            suppliers.push(new User(address(diamond)));
            hevm.label(
                address(suppliers[i]),
                string(abi.encodePacked("Supplier", Strings.toString(i + 1)))
            );
            fillUserBalances(suppliers[i]);
        }
        supplier1 = suppliers[0];
        supplier2 = suppliers[1];
        supplier3 = suppliers[2];

        for (uint256 i = 0; i < 3; i++) {
            borrowers.push(new User(address(diamond)));
            hevm.label(
                address(borrowers[i]),
                string(abi.encodePacked("Borrower", Strings.toString(i + 1)))
            );
            fillUserBalances(borrowers[i]);
        }

        borrower1 = borrowers[0];
        borrower2 = borrowers[1];
        borrower3 = borrowers[2];
    }

    function fillUserBalances(User _user) internal {
        tip(dai, address(_user), INITIAL_BALANCE * WAD);
        tip(wEth, address(_user), INITIAL_BALANCE * WAD);
        tip(usdc, address(_user), INITIAL_BALANCE * 1e6);
    }

    function setContractsLabels() internal {
        hevm.label(address(diamond), "morphoCompound");
        hevm.label(address(proxyAdmin), "ProxyAdmin");
        hevm.label(address(positionsManagerImplV1), "PositionsManagerImplV1");
        hevm.label(address(positionsManager), "PositionsManager");
        hevm.label(address(positionsManagerFacet), "positionsManagerFacet");
        hevm.label(address(marketsManagerImplV1), "MarketsManagerImplV1");
        hevm.label(address(marketsManager), "MarketsManager");
        hevm.label(address(marketsManagerFacet), "marketsManagerFacet");
        hevm.label(address(rewardsManager), "RewardsManager");
        hevm.label(address(morphoToken), "MorphoToken");
        hevm.label(address(comptroller), "Comptroller");
        hevm.label(address(oracle), "CompoundOracle");
        hevm.label(address(dumbOracle), "DumbOracle");
        hevm.label(address(incentivesVault), "IncentivesVault");
        hevm.label(address(treasuryVault), "TreasuryVault");
    }

    function createSigners(uint8 _nbOfSigners) internal {
        while (borrowers.length < _nbOfSigners) {
            borrowers.push(new User(address(diamond)));
            fillUserBalances(borrowers[borrowers.length - 1]);
            suppliers.push(new User(address(diamond)));
            fillUserBalances(suppliers[suppliers.length - 1]);
        }
    }

    function createAndSetCustomPriceOracle() public returns (SimplePriceOracle) {
        SimplePriceOracle customOracle = new SimplePriceOracle();

        IAdminComptroller adminComptroller = IAdminComptroller(address(comptroller));
        hevm.prank(adminComptroller.admin());
        uint256 result = adminComptroller._setPriceOracle(customOracle);
        require(result == 0); // No error

        for (uint256 i = 0; i < pools.length; i++) {
            customOracle.setUnderlyingPrice(pools[i], oracle.getUnderlyingPrice(pools[i]));
        }
        return customOracle;
    }

    function setMaxGasHelper(
        uint64 _supply,
        uint64 _borrow,
        uint64 _withdraw,
        uint64 _repay
    ) public {
        Types.MaxGas memory newMaxGas = Types.MaxGas({
            supply: _supply,
            borrow: _borrow,
            withdraw: _withdraw,
            repay: _repay
        });
        morphoCompound.setMaxGas(newMaxGas);
    }

    function move1000BlocksForward(address _marketAddress) public {
        for (uint256 k; k < 100; k++) {
            hevm.roll(block.number + 10);
            hevm.warp(block.timestamp + 1);
            marketsManager.updateP2PExchangeRates(_marketAddress);
        }
    }

    /// @notice Computes and returns P2P rates for a specific market (without taking into account deltas !).
    /// @param _poolTokenAddress The market address.
    /// @return p2pSupplyRate_ The market's supply rate in P2P (in ray).
    /// @return p2pBorrowRate_ The market's borrow rate in P2P (in ray).
    function getApproxBPYs(address _poolTokenAddress)
        public
        view
        returns (uint256 p2pSupplyRate_, uint256 p2pBorrowRate_)
    {
        ICToken cToken = ICToken(_poolTokenAddress);

        uint256 poolSupplyBPY = cToken.supplyRatePerBlock();
        uint256 poolBorrowBPY = cToken.borrowRatePerBlock();
        uint256 reserveFactor = marketsManager.reserveFactor(_poolTokenAddress);

        // rate = 2/3 * poolSupplyRate + 1/3 * poolBorrowRate.
        uint256 rate = (2 * poolSupplyBPY + poolBorrowBPY) / 3;

        p2pSupplyRate_ = rate - (reserveFactor * (rate - poolSupplyBPY)) / 10_000;
        p2pBorrowRate_ = rate + (reserveFactor * (poolBorrowBPY - rate)) / 10_000;
    }
}
