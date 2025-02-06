// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";

import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test {
    /////////////////////
    // State Variables //
    /////////////////////
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;
    address public wethPriceFeedAddress;
    address public wbtcPriceFeedAddress;
    address public weth;
    address public wbtc;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 100 ether; // 200_000
    uint256 public constant AMOUNT_REDEEM = 5 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10_0000 ether;
    uint256 public constant AMOUNT_MINT = 50_000 ether;
    uint256 public constant AMOUNT_BURN = 10_000 ether;
    uint256 public constant AMOUNT_DEBT = 10_000 ether;
    uint256 public constant ZERO = 0;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant LIQUIDATION_PRECISION = 100;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    /////////////////////
    // Events       //
    /////////////////////

    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);
    ///////////////////
    // Modifier      //
    ///////////////////

    modifier depositedCollateralAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.despositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier startLiquidator() {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approveInternal(LIQUIDATOR, address(dscEngine), STARTING_ERC20_BALANCE);
        dscEngine.despositCollateralAndMintDSC(weth, STARTING_ERC20_BALANCE, STARTING_ERC20_BALANCE);
        dsc.approve(address(dscEngine), STARTING_ERC20_BALANCE);
        vm.stopPrank();
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (wethPriceFeedAddress, wbtcPriceFeedAddress, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }

    ///////////////////////////////////////////
    //// Constructor Tests        ///////////
    ///////////////////////////////////////////

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
        // 15e18 * 2000e8 * 1e10 / 1e18 = 30_000e18
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = dscEngine.getEachCollateralUsdValue(weth, wethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // （100e18 / (2000e8 * 1e10)） * 1e18 = 0.05e18
        // 100 ether / $2000/ether --> $0.05 ETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    ////////////////////////////////////////////////
    //// depositCollateral Tests        ///////////
    ////////////////////////////////////////////////

    function testRevertIfDepositCollateralLessThanZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        uint256 wethAmount = dscEngine.getCollateralAmount(USER, weth);
        assertEq(wethAmount, ZERO);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, ZERO);
        vm.stopPrank();
    }

    function testIsNotAllowedToken() public {
        ERC20Mock anotherToken = new ERC20Mock("ANT", "ANT", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotSupported.selector);
        dscEngine.depositCollateral(address(anotherToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testOnlyDepositCollateral() public depositedCollateral {
        uint256 wethAmount = dscEngine.getCollateralAmount(USER, weth);
        assertEq(wethAmount, AMOUNT_COLLATERAL);
    }

    function testCanDepositCollateralAndGetAccountInfomation() public depositedCollateral {
        uint256 expectedDSCMinted = 0;
        uint256 expectedDepositedCollateralInUsd = dscEngine.getAccountCollateralValueOfUsd(USER);

        (uint256 actualDSCMinted, uint256 actualDepositedCollateral) = dscEngine.getAccountInfomation(USER);

        assertEq(actualDSCMinted, expectedDSCMinted);
        assertEq(actualDepositedCollateral, expectedDepositedCollateralInUsd);
    }

    function testRevertTransferFailedInDeposit() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        // 模拟 transferFrom 返回 false
        vm.mockCall(
            weth,
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(dscEngine), AMOUNT_COLLATERAL),
            abi.encode(false) // 模拟 transferFrom 返回 false
        );
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.clearMockedCalls();
    }

    /**
     * -----------Maybe Something Error ---------------
     *  We deposit 10 ether of WETH, and mint 50_000 ether DSC
     *
     */
    function testDespositCollateralAndMintDSC() public depositedCollateralAndMintDSC {
        uint256 expectedDSCMinted = AMOUNT_MINT;
        uint256 expectedDepositedCollateralInUsd = dscEngine.getAccountCollateralValueOfUsd(USER);

        (uint256 actualDSCMinted, uint256 actualDepositedCollateral) = dscEngine.getAccountInfomation(USER);

        assertEq(actualDSCMinted, expectedDSCMinted);
        assertEq(actualDepositedCollateral, expectedDepositedCollateralInUsd);
    }

    ////////////////////////////////////////////////
    //// redeemCollateral Tests        ///////////
    ////////////////////////////////////////////////
    function testRevertIfRedeemCollateralLessThanZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);

        // first deposit collateral
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 wethAmount = dscEngine.getCollateralAmount(USER, weth);
        assertEq(wethAmount, AMOUNT_COLLATERAL);

        // then redeem collateral
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, ZERO);
        vm.stopPrank();
    }

    function testRedeemCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.despositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        uint256 startingWethBalanceOfUSER = ERC20Mock(weth).balanceOf(USER);

        dscEngine.redeemCollateral(weth, AMOUNT_REDEEM);

        uint256 expectedBalanceOfCollateral = dscEngine.getCollateralAmount(USER, weth);

        assertEq(AMOUNT_COLLATERAL - AMOUNT_REDEEM, expectedBalanceOfCollateral);

        assertEq(startingWethBalanceOfUSER + AMOUNT_REDEEM, ERC20Mock(weth).balanceOf(USER));
    }

    function testRedeemCollateralAndBurnDSC() public depositedCollateralAndMintDSC {
        uint256 startingWethBalanceOfUSER = ERC20Mock(weth).balanceOf(USER);
        uint256 startingDSCBalanceOfUSER = dsc.balanceOf(USER);

        vm.startPrank(USER);
        dsc.approve(address(dscEngine), AMOUNT_BURN);
        dscEngine.redeemCollateralForDSC(weth, AMOUNT_REDEEM, AMOUNT_BURN);

        uint256 endingWethBalanceOfUSER = ERC20Mock(weth).balanceOf(USER);
        uint256 endingDSCBalanceOfUSER = dsc.balanceOf(USER);

        assertEq(endingDSCBalanceOfUSER, startingDSCBalanceOfUSER - AMOUNT_BURN);
        assertEq(endingWethBalanceOfUSER, startingWethBalanceOfUSER + AMOUNT_REDEEM);
    }

    function testRevertTransferFailedInRedeem() public depositedCollateral {
        vm.startPrank(USER);
        // 模拟 transfer 返回 false
        vm.mockCall(
            weth,
            abi.encodeWithSelector(IERC20.transfer.selector, USER, AMOUNT_COLLATERAL),
            abi.encode(false) // 模拟 transferFrom 返回 false
        );
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dscEngine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.clearMockedCalls();
    }

    /**
     *
     * 1. If I only deposit collateral, I don't mint any DSC
     * 2. I can't redeem collateral, it will make a panic because healthfactor division or modulo by zero
     * 3. I modify the calculateHealthFactor function, if the dsc minted is zero, it will return type(uint256).max
     */
    function testCanEmitRedeemEvent() public /*depositedCollateralAndMintDSC*/ depositedCollateral {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_REDEEM);
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, AMOUNT_REDEEM);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////
    //// liquidation Tests        ///////////
    ////////////////////////////////////////////////

    function testRevertIfLiquidateDebtAmountLessThanZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.liquidate(weth, USER, ZERO);
    }

    function testRevertIfUserHealthFactorIsOK() public depositedCollateralAndMintDSC startLiquidator {
        vm.startPrank(LIQUIDATOR);

        uint256 startingHealthFactor = dscEngine.getHealthFactor(USER);
        console.log("Starting Health Factor: ", startingHealthFactor);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOk.selector);
        dscEngine.liquidate(weth, USER, AMOUNT_DEBT);
    }

    function testRevertIfHealthFactorIsNotImproved() public depositedCollateralAndMintDSC startLiquidator {
        int256 updateWethPrice = 200e8;
        MockV3Aggregator(wethPriceFeedAddress).updateAnswer(updateWethPrice);
        uint256 startingHealthFactorOfUser = dscEngine.getHealthFactor(USER);
        console.log("Starting Health Factor: ", startingHealthFactorOfUser);

        vm.startPrank(LIQUIDATOR);

        vm.expectRevert(DSCEngine.DSCEnigne__HealthFactorIsNotImproved.selector);
        dscEngine.liquidate(weth, USER, AMOUNT_DEBT);
    }

    // function testLiquidation() public depositedCollateralAndMintDSC startLiquidator {
    //     int256 updateWethPrice = 200e8;
    //     MockV3Aggregator(wethPriceFeedAddress).updateAnswer(updateWethPrice);

    //     console.log("User Health Factor:", dscEngine.getHealthFactor(USER));
    //     assert(dscEngine.getHealthFactor(USER) < dscEngine.getMinimumHealthFactor());
    //     // health factor
    //     // we need to calculate the debt of the user

    //     vm.startPrank(LIQUIDATOR);
    //     uint256 previousDSCAmountOfLiquidator = dsc.balanceOf(LIQUIDATOR);
    //     uint256 previousWethAmountOfLiquidator = ERC20Mock(weth).balanceOf(LIQUIDATOR);

    //     uint256 liquidationAmount = AMOUNT_MINT / 2;

    //     dscEngine.liquidate(weth, USER, liquidationAmount);

    //     uint256 tokenAmountFromDebtCovered = dscEngine.getTokenAmountFromUsd(weth, liquidationAmount);
    //     uint256 expectedWethGain = (tokenAmountFromDebtCovered * (100 + dscEngine.getLiquidationBonus())) / 100;

    //     uint256 endDSCAmountOfLiquidator = dsc.balanceOf(LIQUIDATOR);
    //     uint256 endWethAmountOfLiquidator = ERC20Mock(weth).balanceOf(LIQUIDATOR);

    //     assertEq(endDSCAmountOfLiquidator, previousDSCAmountOfLiquidator - liquidationAmount, "DSC balance mismatch");
    //     assertEq(endWethAmountOfLiquidator, previousWethAmountOfLiquidator + expectedWethGain, "WETH balance mismatch");
    // }

    ////////////////////////////////////////////////
    //// HealthFactor Tests           ///////////
    ////////////////////////////////////////////////
    function testFactorIsOk() public depositedCollateralAndMintDSC {
        console.log("TotalERC20Mock", ERC20Mock(weth).balanceOf(USER) + dscEngine.getCollateralAmount(USER, weth));

        (uint256 actualDSCMinted, uint256 totalDepositedCollateralInUsd) = dscEngine.getAccountInfomation(USER);
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(totalDepositedCollateralInUsd, actualDSCMinted);

        console.log("TotalDSC Mint", dsc.balanceOf(USER));
        console.log("ToralDepositedCollateral", dscEngine.getCollateralAmount(USER, weth));
        console.log("TotalDepositedCollateralInUsd", dscEngine.getAccountCollateralValueOfUsd(USER)); // 2e22

        // how to calculate the factor collateral value of usd 2e22 / total minted DSC 5e22  get the factor 2e17
        uint256 startingHealthFactor = dscEngine.getHealthFactor(USER);

        assertEq(startingHealthFactor, expectedHealthFactor);
    }

    /**
     * @notice When Collateral value is Less than my minted DSC, I can't mint DSC anymore.
     */
    function testRevertIfMintDSCBrakeHealthFactor() public depositedCollateralAndMintDSC {
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        console.log("Health Factor: ", healthFactor);
        vm.startPrank(USER);

        uint256 collateralInUsd = dscEngine.getAccountCollateralValueOfUsd(USER);
        uint256 willMintDSC = dsc.balanceOf(USER) + AMOUNT_MINT * 2;

        uint256 badHealthFactor = dscEngine.calculateHealthFactor(collateralInUsd, willMintDSC);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, badHealthFactor));
        dscEngine.mintDSC(AMOUNT_MINT * 2);
        vm.stopPrank();
    }

    /**
     * @notice If copllateral price is going down, the health factor will be below 1
     */
    function testFactorCanBelowOne() public depositedCollateralAndMintDSC {
        int256 updateWethPrice = 200e8;

        MockV3Aggregator(wethPriceFeedAddress).updateAnswer(updateWethPrice);
        (uint256 actualDSCMinted, uint256 totalDepositedCollateralInUsd) = dscEngine.getAccountInfomation(USER);
        uint256 calHealthFactor = dscEngine.calculateHealthFactor(totalDepositedCollateralInUsd, actualDSCMinted);

        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        assertEq(healthFactor, calHealthFactor);
    }

    ////////////////////////////////////////////////
    //// Mint Tests                 ///////////
    ////////////////////////////////////////////////
    // now i don't know need to deposit collateral before mint DSC to test
    function testRevertIfMintAmountIsLessThanZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.mintDSC(ZERO);
        vm.stopPrank();
    }

    function testMint() public depositedCollateral {
        vm.startPrank(USER);

        dscEngine.mintDSC(AMOUNT_MINT);

        assertEq(AMOUNT_MINT, dsc.balanceOf(USER));
        vm.stopPrank();
    }

    /**
     *
     * -------------May be we dont deposit collateral before mint DSC
     * nonono it has a health factor check
     */
    // function testRevertMintFailed() public depositedCollateral {
    //     vm.startPrank(USER);
    //     vm.mockCall(
    //         address(dsc),
    //         abi.encodeWithSelector(DecentralizedStableCoin.mint.selector, msg.sender, AMOUNT_MINT),
    //         abi.encode(false)
    //     );
    //     vm.expectRevert(DSCEngine.DSCEngine__MintedFailed.selector);

    //     dscEngine.mintDSC(AMOUNT_MINT);

    //     vm.stopPrank();
    //     vm.clearMockedCalls();
    //     uint256 healthFactor = dscEngine.getHealthFactor(USER);
    //     console.log("Health Factor: ", healthFactor);
    // }

    ////////////////////////////////////////////////
    //// Burn Tests                 ///////////
    ////////////////////////////////////////////////

    function testRevertIfBurnAmountIsLessThanZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.burnDSC(ZERO);
    }

    function testBurnDSC() public depositedCollateralAndMintDSC {
        vm.startPrank(USER);
        // user need to approve the DSCEngine to burn DSC
        dsc.approve(address(dscEngine), AMOUNT_BURN);
        dscEngine.burnDSC(AMOUNT_BURN);

        assertEq(AMOUNT_MINT - AMOUNT_BURN, dsc.balanceOf(USER));
    }

    function testBurnOnlyUSERHasDSC() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDSC(1);
    }

    /////////////////////////////////
    ////View Functions Tests      //
    ////////////////////////////////

    function testGetLiquidationBonus() public view {
        uint256 expectedLiquidationBonus = 10;
        uint256 actualLiquidationBonus = dscEngine.getLiquidationBonus();
        assertEq(expectedLiquidationBonus, actualLiquidationBonus);
    }

    function testGetMinimumHealthFactor() public view {
        uint256 expectedMinimumHealthFactor = MIN_HEALTH_FACTOR;
        uint256 actualMinimumHealthFactor = dscEngine.getMinimumHealthFactor();
        assertEq(expectedMinimumHealthFactor, actualMinimumHealthFactor);
    }
}
