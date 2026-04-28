// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";

/**
 * @title InterestRateModel
 * @notice LendCore Pro V1 线性利率模型
 * @dev
 * 这个模型根据资金池利用率计算借款利率和存款利率。
 *
 * 核心公式：
 * utilization = totalBorrow / totalLiquidity
 * borrowRate = baseRate + utilization * slope
 *
 * 其中：
 * - baseRate 是基础年化利率
 * - slope 是利用率敏感系数
 * - 返回值都是 WAD 精度，1e18 = 100%
 */
contract InterestRateModel is IInterestRateModel {
    uint256 public constant WAD = 1e18;

    /**
     * @notice 年化基础借款利率
     * @dev 0.02e18 = 2%
     */
    uint256 public immutable baseRate;

    /**
     * @notice 利率斜率
     * @dev 0.20e18 = 20%
     */
    uint256 public immutable slope;

    /**
     * @notice 协议准备金比例
     * @dev 0.10e18 = 10%
     */
    uint256 public immutable reserveFactor;

    constructor(
        uint256 baseRate_,
        uint256 slope_,
        uint256 reserveFactor_
    ) {
        require(reserveFactor_ <= WAD, "reserve factor too high");

        baseRate = baseRate_;
        slope = slope_;
        reserveFactor = reserveFactor_;
    }

    /**
     * @notice 获取资金池利用率
     * @param totalLiquidity 总流动性，建议传 cash + totalBorrow
     * @param totalBorrow 总借款
     * @return utilization 利用率，WAD 精度
     */
    function getUtilizationRate( 
        uint256 totalLiquidity,
        uint256 totalBorrow
    ) public pure returns (uint256 utilization) {
        if (totalLiquidity == 0 || totalBorrow == 0) {
            return 0;
        }

        return (totalBorrow * WAD) / totalLiquidity;
    }

    /**
     * @notice 获取借款年化利率
     * @param asset 资产地址，V1 暂时不用，预留给后续多资产差异化利率
     * @param totalSupply 总流动性，语义上这里表示 totalLiquidity
     * @param totalBorrow 总借款
     * @return 借款年化利率，WAD 精度
     */
    function getBorrowRate(
        address asset,
        uint256 totalSupply,
        uint256 totalBorrow
    ) external view returns (uint256) {
        asset;

        uint256 utilization = getUtilizationRate(totalSupply, totalBorrow);

        return baseRate + ((utilization * slope) / WAD);
    }

    /**
     * @notice 获取存款年化利率
     * @param asset 资产地址，V1 暂时不用
     * @param totalSupply 总流动性，语义上这里表示 totalLiquidity
     * @param totalBorrow 总借款
     * @return 存款年化利率，WAD 精度
     *
     * 简化公式：
     * supplyRate = borrowRate * utilization * (1 - reserveFactor)
     */
    function getSupplyRate(
        address asset,
        uint256 totalSupply,
        uint256 totalBorrow
    ) external view returns (uint256) {
        uint256 borrowRate = this.getBorrowRate(
            asset,
            totalSupply,
            totalBorrow
        );

        uint256 utilization = getUtilizationRate(totalSupply, totalBorrow);

        return
                (((borrowRate * utilization) / WAD) *
                    (WAD - reserveFactor)) / WAD;
    }
}