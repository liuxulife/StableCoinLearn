// // SPDX-License-Identifier: MIT
// // Have our invariant aka properties
// // What are out invariant aka properties?

// // 1. The total supply DSC should less than the total value of the collateral
// // 2. The Getter view funciton should never revert <- evergreen invariant
// pragma solidity ^0.8.18;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
// import {DeployDSC} from "script/DeployDSC.s.sol";
// import {DSCEngine} from "src/DSCEngine.sol";
// import {HelperConfig} from "script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract InvariantTest is StdInvariant, Test {
//     DeployDSC public deployer;
//     DecentralizedStableCoin public dsc;
//     DSCEngine public dscEngine;
//     HelperConfig public config;
//     address public weth;
//     address public wbtc;

//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, dscEngine, config) = deployer.run();
//         (,, weth, wbtc,) = config.activeNetworkConfig();
//         targetContract(address(dscEngine));
//     }

//     function invariant__TotalCollateralValueShouldBeGreaterThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();

//         uint256 wethAmount = IERC20(weth).balanceOf(address(dscEngine));
//         uint256 wbtcAmount = IERC20(wbtc).balanceOf(address(dscEngine));
//         uint256 wethValue = dscEngine.getEachCollateralUsdValue(weth, wethAmount);
//         uint256 wbtcValue = dscEngine.getEachCollateralUsdValue(wbtc, wbtcAmount);
//         uint256 totalValue = wethValue + wbtcValue;

//         // require(totalValue > totalSupply, "Invariant broken: totalValue <= totalSupply");
//         console.log("totalSupply", totalSupply);
//         console.log("wethValue", wethValue);
//         console.log("wbtcValue", wbtcValue);

//         assert(totalValue > totalSupply);
//     }
// }
