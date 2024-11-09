// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";

contract DSCoinTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    address public USER = makeAddr("user");

    uint256 public constant AMOUNT_MINT = 10 ether;
    uint256 public constant ZERO = 0;
    uint256 public constant AMOUNT_BURN = 5 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine,) = deployer.run();
    }

    ///////////////////////////////////////////
    //// Constructor Tests        ///////////
    ///////////////////////////////////////////

    function testTheDSCoinOwner() public view {
        assertEq(dsc.owner(), address(dscEngine));
    }

    function testDSCNameAndSymbol() public view {
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
    }

    ///////////////////////////////////////////
    //// Mint Tests                 ///////////
    ///////////////////////////////////////////

    modifier dscEnginePrank() {
        vm.startPrank(address(dscEngine));
        _;
        vm.stopPrank();
    }

    // the owner of DSCoin is DSCEngine
    function testOnlyOwnerCanMint() public dscEnginePrank {
        bool success = dsc.mint(USER, AMOUNT_MINT);
        assertEq(success, true);

        // Reason: vm.prank: cannot override an ongoing prank with a single vm.prank; use vm.startPrank to override the current prank]  vm.prank(USER);
        vm.startPrank(USER);
        //要使用带参数的自定义 错误类型与expectRevert，请对错误类型进行 ABI 编码。
        // vm.expectRevert(
        //     abi.encodeWithSelector(CustomError.selector, 1, 2)
        // );

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));

        bool state = dsc.mint(USER, AMOUNT_MINT);
        assertEq(state, false);
    }

    function testRevertIfToAddressIsZero() public dscEnginePrank {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__NotZeroAddress.selector);
        dsc.mint(address(0), AMOUNT_MINT);
    }

    function testRevertMintAmountMustBeMoreThanZero() public dscEnginePrank {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(USER, ZERO);
    }

    ///////////////////////////////////////////
    //// Burn Tests                 ///////////
    ///////////////////////////////////////////

    // the owner of DSCoin is DSCEngine
    function testOnlyOwnerCanBurn() public {
        // Regardless of the owner permission, ensure the use have the DSC token.
        vm.startPrank(dsc.owner());
        dsc.mint(dsc.owner(), AMOUNT_MINT);
        dsc.burn(AMOUNT_BURN);
        assertEq(dsc.balanceOf(dsc.owner()), AMOUNT_MINT - AMOUNT_BURN);

        vm.stopPrank();

        vm.prank(USER);
        //要使用带参数的自定义 错误类型与expectRevert，请对错误类型进行 ABI 编码。
        // vm.expectRevert(
        //     abi.encodeWithSelector(CustomError.selector, 1, 2)
        // );

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        dsc.burn(AMOUNT_MINT);
    }

    function testRevertBurnAmountMustBeMoreThanZero() public dscEnginePrank {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(ZERO);
    }

    function testRevertIfBurnAmountExceedsBalance() public dscEnginePrank {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(AMOUNT_MINT);
    }
}
