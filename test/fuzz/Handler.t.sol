// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint96 public constant MAX_AMOUNT_COLLATERAL = type(uint96).max;
    uint256 public timeDSCMinted;
    uint256 public timeCollateralRedeemed;
    address[] public userCollateralAddressesDeposited;

    MockV3Aggregator public wethPriceFeed;
    MockV3Aggregator public wbtcPriceFeed;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;
        address[] memory addresses = dscEngine.getCollateralAddresses();
        weth = ERC20Mock(addresses[0]);
        wbtc = ERC20Mock(addresses[1]);

        wethPriceFeed = MockV3Aggregator(dscEngine.getCollateralPriceFeed(address(weth)));
        wbtcPriceFeed = MockV3Aggregator(dscEngine.getCollateralPriceFeed(address(wbtc)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_AMOUNT_COLLATERAL);
        collateral.mint(msg.sender, amountCollateral);

        vm.startPrank(msg.sender);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        userCollateralAddressesDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 amountCollateralMax = dscEngine.getCollateralAmount(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, amountCollateralMax);
        if (amountCollateral == 0) {
            return;
        }
        // vm.assume(amountCollateral != 0);

        uint256 healthFactor = dscEngine.getHealthFactor(msg.sender);
        console.log("health factor", healthFactor);
        console.log("isGreaterThanMinimumHealthFactor", healthFactor > dscEngine.getMinimumHealthFactor());
        // if (healthFactor < dscEngine.getMinimumHealthFactor()) {
        //     return;
        // }
        vm.prank(msg.sender);
        // vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        // vm.stopPrank();
        timeCollateralRedeemed++;
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (userCollateralAddressesDeposited.length == 0) {
            return;
        }
        address sender = userCollateralAddressesDeposited[addressSeed % userCollateralAddressesDeposited.length];

        (uint256 tatoalMintedDSC, uint256 collateralOfUsd) = dscEngine.getAccountInfomation(sender);
        int256 totalNeedToMint = int256((collateralOfUsd / 2)) - int256(tatoalMintedDSC);
        if (totalNeedToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(totalNeedToMint));
        if (amount <= 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        timeDSCMinted++;
    }

    // function updatePrice(uint96 priceSeed) public {
    //     int256 price = int256(uint256(priceSeed));
    //     wethPriceFeed.updateAnswer(price);
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
