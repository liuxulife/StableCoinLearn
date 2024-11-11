// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
/**
 * @title DSCEngine
 * @author ThalesLiu (Learn from Patrick)
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI has no governance, no fees, and was only backed by WETH and WBTC
 *
 * Our DSC system should always be "over-collateralized". At no point,
 * should the value of all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS(DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    ///////////////////
    // Error        //
    ///////////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotSupported();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakHealthFactor(uint256 healthFactor);
    error DSCEngine__MintedFailed();
    error DSCEngine__HealthFactorIsOk();
    error DSCEnigne__HealthFactorIsNotImproved();

    /////////////////////
    // State Variables //
    /////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    /////////////////////
    // Events          //
    /////////////////////

    event CollateralDesposited(address indexed user, address indexed token, uint256 indexed amount);
    // event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    ///////////////////
    // Modifier      //
    ///////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    /////////////////////
    // Functions       //
    /////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////////
    // External Functions       //
    //////////////////////////////

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of the token to deposit as collateral
     * @param amountDscToMint The amount of DSC to mint (Decentralized Stable Coin)
     * @notice this funciont is a combination of depositCollateral and mint
     */
    function despositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @notice follows CEI pattern (Check-Effect-Interact)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of the token to deposit as collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDesposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // transfer the collateral from the user to this contract
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The address of the token to redeem as collateral
     * @param amountCollateral The amount of the token to redeem as collateral
     * @param amountDSCToBurn The amount of DSC to burn
     * @notice this funciont is a combination of redeemCollateral and burnDSC
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)
        external
    {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // we have already check the health factor in the redeemCollateral function
    }

    // in order to redeem collateral, the user must have more collateral than the minimum threshold
    // DRY: Don't Repeat Yourself
    // CEI: Check-Effect-Interact
    // when we reedem our collateral, maybe we will break the health factor and to prevent that we should burn some DSC
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorBroken(msg.sender);
    }

    /**
     * @notice follows CEI pattern (Check-Effect-Interact)
     * @param amountDscToMint The amount of DSC to mint (Decentralized Stable Coin)
     * @notice they must have more collateral than the minimum threshold or the value of the DSC they are minting
     */
    function mintDSC(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if the use mint too much (150 $DSC -> 100$ collateral)
        _revertIfHealthFactorBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintedFailed();
        }
    }

    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        // why we need to check the health factor here? we burn the DSC, generally, the health factor will be increased, we add this to help auditing in the future.
        _revertIfHealthFactorBroken(msg.sender);
    }

    /**
     * @param collateralAddress The address of the collateral to liquidate
     * @param user The address of the user to liquidate
     * @param debtToCover the value of the debt that the liquidator want to cover (1e18)
     * @notice You can partially liquiddate a user
     * @notice You will get a liquidation bonus for taking users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize liquidators
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follows CEI pattern (Check-Effect-Interact)
     */
    function liquidate(address collateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOk();
        }

        // we want to liquidate the user for the amount of debt they owe
        // 1. we need to burn their DSC and 2. we need to take their collateral
        // Bad user : $120ETH , $100DSC
        // debtToCover = $100DSC
        // The $100DSC --> $ ???ETH
        // 将 debtToCover 的 USD 值转换为相应数量的 collateralAddress 抵押资产。
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralAddress, debtToCover);
        // and give a 10% bonus to the liquidator
        // So we are giving the liquidator $110ETH for the $100DSC
        // we should implement the feature to liquidate in the event the protocol is insolvent
        // And sweep extra money to the treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = bonusCollateral + tokenAmountFromDebtCovered;

        _redeemCollateral(collateralAddress, totalCollateralToRedeem, user, msg.sender);

        // burn the user's DSC, and the msg.sender will use DSC pay for it to get the user's collateral and bonus
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor < startingUserHealthFactor) {
            revert DSCEnigne__HealthFactorIsNotImproved();
        }
        _revertIfHealthFactorBroken(msg.sender);
    }

    ////////////////////////////////////////////
    // Internal & Private Functions       //
    ////////////////////////////////////////////

    // 1. Check the health factor (do they have enough collateral)
    // 2. Revert if they don't
    /**
     *
     * @param user The address of the user to check the health factor
     * @notice If the user's health factor is below the minimum health factor, then revert
     * @notice The minimum health factor is 1
     * @notice the calculated health factor precision is 1e18
     * and why can compare 1e18 with 1？
     */
    function _revertIfHealthFactorBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreakHealthFactor(userHealthFactor);
        }
    }

    /**
     *  Returns how close to liquidation a user is
     *  @param user The address of the user to check the health factor
     *  @return healthFactor The health factor of the user (1e18)
     *  @notice healthfactor = (collateralValue * threshold) / totalDSCMinted
     *  @notice If a user get below 1, then they will be liquidated
     *  @notice Return HealthFactor in 1e18 precision
     *
     */
    function _healthFactor(address user) private view returns (uint256) {
        // What we need
        // 1. total collateral value of usd
        // 2. total DSC minted
        (uint256 totalDscMinted, uint256 collateralValueOfUsd) = _getAccountInfomation(user);

        uint256 healthFactor = _calculateHealthFactor(collateralValueOfUsd, totalDscMinted);
        return healthFactor;
    }

    /**
     *
     * @param collateralValueOfUsd  The total value of the user's collateral in USD (1e18)
     * @param amountDSC  The total amount of DSC minted by the user
     * @return healthFactor The health factor of the user (1e18)
     */
    function _calculateHealthFactor(uint256 collateralValueOfUsd, uint256 amountDSC) private pure returns (uint256) {
        /**
         * collateralAdjustedForThreshold means the value of the collateral after the liquidation threshold is applied
         * now the threshold is 50% is the LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION
         * 100 $ETH -> 50 $ ==> 100$ETH * 50 / 100 = 50$
         */
        if (amountDSC == 0) {
            return type(uint256).max;
        }

        // 50/100 we need know the collateralValueOfUsd's precision
        uint256 collateralAdjustedForThreshold = (collateralValueOfUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // 150$ ETH / 100$  = 1.5
        // 150 * 50 = 7500 / 100 = 75 / 100  < 1
        // we need to ajust the precision make the usd precision is 1e18 and the dsc precision is 1e18
        uint256 healthFactor = (collateralAdjustedForThreshold * PRECISION) / amountDSC;
        return healthFactor;
    }

    /**
     *
     * @param user The address of the user to get the account information
     * @return totalDscMinted  The total amount of DSC minted by the user
     * @return collateralValueOfUsd  The total value of the user's collateral in USD (1e18)
     */
    function _getAccountInfomation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueOfUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueOfUsd = getAccountCollateralValueOfUsd(user);
    }

    // when i write a redeem test it return ReentrancyGuardReentrantCall error and maybe the nonReentrant modifier is recursive used
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
        moreThanZero(amountCollateral)
    // nonReentrant
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @param amount The amount of DSC to burn
     * @param onBehalf The address of the user to burn the DSC on behalf of (who's dsc need to be burned)
     * @param dscFromWho The address of the user to burn the DSC from (who pay the dsc)
     * @dev Low-level private function to burn DSC, do not call unless the function calling it is and checking for health facotrs being broken
     */
    function _burnDSC(uint256 amount, address onBehalf, address dscFromWho) private moreThanZero(amount) {
        s_DSCMinted[onBehalf] -= amount;

        bool success = i_dsc.transferFrom(dscFromWho, address(this), amount);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    /////////////////////////////////////////////
    // Public & External View Functions       //
    /////////////////////////////////////////////

    /**
     * @param token The address of the token to get the amount of in USD
     * @param amountUsdInWei The value of the token in USDWei (1e18)
     * @return The amount of the token
     * @notice The Result Precision is 1e18
     */
    function getTokenAmountFromUsd(address token, uint256 amountUsdInWei) public view returns (uint256) {
        // price of ETH (token) and its precision is 1e8
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // We get the usdInwei (maybe is from the getusdValue function) and we need to adjust the price precision to 1e18 and we use amountUsdInWei divide the price and adjust result precision to 1e18
        // ($10e18 * 1e18) / ($2000e8 * 1e10) = 5e18 <--> 10e18 / (20000e8 * 1e10) * 1e18
        return (amountUsdInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     *
     * @param user The address of the user to get the collateral value of
     * @return totalCollateralValueOfUsd The total value of the user's collateral in USD (1e18)
     * @notice The Result Precision is 1e18
     */
    function getAccountCollateralValueOfUsd(address user) public view returns (uint256 totalCollateralValueOfUsd) {
        // 1. get each token value in USD (collateral * price) need to loop all the tokens types
        // 2. get the total value of all the tokens
        // 3. return the total value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueOfUsd += getEachCollateralUsdValue(token, amount);
        }

        return totalCollateralValueOfUsd;
    }

    /**
     * @param token The address of the token to get the value of
     * @param amount The amount of the token to get the value of
     * @return The value of the token in USDInWei（1e18)
     * @notice The Result Precision is 1e18
     */
    function getEachCollateralUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // the price precision is 1e8 and the amount precision is 1e18 so we need to adjust the price precision to 1e18 and then we multiply the price and the amount and then divide the precision to get the usd value result (1e18)
        return (((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION);
    }

    function getAccountInfomation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueOfUsd)
    {
        (totalDscMinted, collateralValueOfUsd) = _getAccountInfomation(user);
    }

    function getCollateralAmount(address user, address token) public view returns (uint256 amount) {
        return s_collateralDeposited[user][token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        uint256 healthFactor = _healthFactor(user);
        return healthFactor;
    }

    function calculateHealthFactor(uint256 collateralValueOfUsd, uint256 amountDSC) public pure returns (uint256) {
        return _calculateHealthFactor(collateralValueOfUsd, amountDSC);
    }

    function getMinimumHealthFactor() public pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationBonus() public pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getCollateralAddresses() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralPriceFeed(address token) public view returns (address) {
        return s_priceFeeds[token];
    }
}
