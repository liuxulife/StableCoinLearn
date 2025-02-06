// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author ThalesLiu learned from Pratric
 * @notice The library is used to check the chainlink Oracle for stale data
 * if a price is stale, the function will revert. And render the system unstale by design
 * we want to freeze the DSCEngine system if the price is stale
 *
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIME_OUT = 3 hours; // 3 * 60 * 60 =  10800 seconds

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        if (block.timestamp - updatedAt > TIME_OUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
