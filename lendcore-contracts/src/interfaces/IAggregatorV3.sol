// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAggregatorV3
 * @notice Chainlink AggregatorV3Interface 的最小接口
 * @dev
 * 为了减少依赖复杂度，这里只定义当前项目需要的函数。
 */
interface IAggregatorV3 {
    function decimals() external view returns (uint8);

    function latestRoundData()
    external
    view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}