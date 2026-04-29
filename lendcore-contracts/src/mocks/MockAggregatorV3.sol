// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockAggregatorV3
 * @notice 测试用 Chainlink AggregatorV3 风格价格源
 * @dev
 * 这个合约模拟 Chainlink Price Feed 的核心接口：
 * - decimals()
 * - latestRoundData()
 *
 * 价格使用 int256，是为了和 Chainlink 接口保持一致。
 */
contract MockAggregatorV3 {
    uint8 private immutable i_decimals;

    int256 private s_answer;
    uint256 private s_updatedAt;
    uint80 private s_roundId;

    constructor(uint8 decimals_, int256 initialAnswer_) {
        i_decimals = decimals_;
        s_answer = initialAnswer_;
        s_updatedAt = block.timestamp;
        s_roundId = 1;
    }

    function decimals() external view returns (uint8) {
        return i_decimals;
    }

    function setAnswer(int256 newAnswer) external {
        s_answer = newAnswer;
        s_updatedAt = block.timestamp;
        s_roundId++;
    }

    function setAnswerWithTimestamp(
        int256 newAnswer,
        uint256 updatedAt_
    ) external {
        s_answer = newAnswer;
        s_updatedAt = updatedAt_;
        s_roundId++;
    }

    function latestRoundData()
    external
    view
    returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    )
    {
        return (s_roundId, s_answer, s_updatedAt, s_updatedAt, s_roundId);
    }
}