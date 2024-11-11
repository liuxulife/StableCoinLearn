// SPDX-License-Identifier: MIT
// Have our invariant aka properties
// What are out invariant aka properties?

// 1. The total supply DSC should less than the total value of the collateral
// 2. The Getter view funciton should never revert <- evergreen invariant
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    Handler public handler;
    HelperConfig public config;
    address public weth;
    address public wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(dscEngine));
        handler = new Handler(dsc, dscEngine);
        targetContract(address(handler));
        // if we dont deposit collateral we dont redeem the collateral
    }

    function invariant__TotalCollateralValueShouldBeGreaterThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();

        uint256 wethAmount = IERC20(weth).balanceOf(address(dscEngine));
        uint256 wbtcAmount = IERC20(wbtc).balanceOf(address(dscEngine));
        uint256 wethValue = dscEngine.getEachCollateralUsdValue(weth, wethAmount);
        uint256 wbtcValue = dscEngine.getEachCollateralUsdValue(wbtc, wbtcAmount);
        uint256 totalValue = wethValue + wbtcValue;

        // require(totalValue > totalSupply, "Invariant broken: totalValue <= totalSupply");
        console.log("totalSupply", totalSupply);
        console.log("wethValue", wethValue);
        console.log("wbtcValue", wbtcValue);
        console.log("wbtc Amount", wbtcAmount);
        console.log("Time DSC Minted", handler.timeDSCMinted());
        console.log("Time Collateral Redeemed", handler.timeCollateralRedeemed());

        assert(totalValue >= totalSupply);
    }

    function invariant__GetterViewFunctionShouldNeverRevert() public view {
        // we can call the getter view function without reverting
        //   "getAccountCollateralValueOfUsd(address)": "e5cf9cd0",
        //   "getAccountInfomation(address)": "ea139d93",
        //   "getCollateralAddresses()": "1834f2a4",
        //   "getCollateralAmount(address,address)": "1e40e53a",
        //   "getCollateralPriceFeed(address)": "19f56d56",
        //   "getEachCollateralUsdValue(address,uint256)": "99ba98e7",
        //   "getHealthFactor(address)": "fe6bcd7c",
        //   "getLiquidationBonus()": "59aa9e72",
        //   "getMinimumHealthFactor()": "54fc49e2",
        //   "getTokenAmountFromUsd(address,uint256)": "afea2e48",
        dscEngine.getAccountCollateralValueOfUsd(msg.sender);
        dscEngine.getAccountInfomation(msg.sender);
        dscEngine.getCollateralAddresses();
        dscEngine.getCollateralAmount(msg.sender, weth);
        dscEngine.getCollateralPriceFeed(weth);
        dscEngine.getEachCollateralUsdValue(weth, 1);
        dscEngine.getHealthFactor(msg.sender);
        dscEngine.getLiquidationBonus();
        dscEngine.getMinimumHealthFactor();
        dscEngine.getTokenAmountFromUsd(weth, 1);
    }
}
