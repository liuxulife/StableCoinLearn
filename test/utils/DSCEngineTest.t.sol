// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;
    address public wethPriceFeedAddress;
    address public wbtcPriceFeedAddress;
    address public weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wethPriceFeedAddress, wbtcPriceFeedAddress, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////////////////////////
    //// Constructor Tests        ///////////
    ///////////////////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenAddressesIsNotSameLengthAsPriceFeedAddresses() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethPriceFeedAddress);
        priceFeedAddresses.push(wbtcPriceFeedAddress);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        // DSCEngine dscEngine =
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////////////////////
    //// Price Tests        ///////////
    ////////////////////////////////////

    function testGetUsdValue() public view {
        uint256 wethAmount = 15e18;
        // 15e18 * 2000ETH -->
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, wethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // $2000 ETH / $100 --> $0.05 ETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    ////////////////////////////////////////////////
    //// depositCollateral Tests        ///////////
    ////////////////////////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(address(weth), address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testIsNotAllowedToken() public {
        ERC20Mock anotherToken = new ERC20Mock("ANT", "ANT", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotSupported.selector);
        dscEngine.depositCollateral(address(anotherToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfomation() public depositedCollateral {
        uint256 expectedDSCMinted = 0;
        uint256 expectedDepositedCollateralInUsd = dscEngine.getAccountCollateralValueOfUsd(USER);

        (uint256 actualDSCMinted, uint256 actualDepositedCollateral) = dscEngine.getAccountInfomation(USER);

        assertEq(actualDSCMinted, expectedDSCMinted);
        assertEq(actualDepositedCollateral, expectedDepositedCollateralInUsd);
    }
}
