// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IInterestRateModel
 * @notice LendCore Pro 利率模型接口
 * @dev
 * 利率模型负责根据资金池利用率计算利率。
 *
 * 核心概念：
 * utilization = totalBorrow / totalSupply
 *
 * 一般规律：
 * - 借得越多，利用率越高，借款利率越高
 * - 借得越少，利用率越低，借款利率越低
 */
interface IInterestRateModel {
    /**
     * @notice 获取借款利率
     * @param asset 资产地址
     * @param totalSupply 该资产总存入量
     * @param totalBorrow 该资产总借款量
     * @return 借款利率，WAD 精度
     *
     * V1 可以用线性模型：
     * borrowRate = baseRate + utilization * slope
     */
    function getBorrowRate(
        address asset,
        uint256 totalSupply,
        uint256 totalBorrow
    ) external view returns (uint256);

    /**
     * @notice 获取存款利率
     * @param asset 资产地址
     * @param totalSupply 该资产总存入量
     * @param totalBorrow 该资产总借款量
     * @return 存款利率，WAD 精度
     *
     * V1 可以用：
     * supplyRate = borrowRate * utilization * (1 - reserveFactor)
     */
    function getSupplyRate(
        address asset,
        uint256 totalSupply,
        uint256 totalBorrow
    ) external view returns (uint256);
}