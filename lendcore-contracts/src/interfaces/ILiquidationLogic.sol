// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ILiquidationLogic
 * @notice LendCore Pro 清算逻辑接口
 * @dev
 * 这个接口负责清算相关的计算。
 *
 * 清算的核心问题：
 * 1. 用户是否可被清算？
 * 2. 清算人最多能替用户还多少债务？
 * 3. 清算人偿还债务后，可以获得多少抵押品？
 */
interface ILiquidationLogic {
    /**
     * @notice 判断用户是否可被清算
     * @param user 被检查用户
     * @return true 表示可清算，false 表示不可清算
     *
     * 判断标准：
     * 用户健康因子 < 1e18
     */
    function isLiquidatable(
        address user
    ) external view returns (bool);

    /**
     * @notice 获取用户某债务资产的最大可清算数量
     * @param user 被清算用户
     * @param debtAsset 债务资产地址
     * @return 最大可清算债务数量
     *
     * 业务说明：
     * - 通常不会一次性清算全部债务
     * - V1 可以设置 close factor = 50%
     */
    function getMaxLiquidatableDebt(
        address user,
        address debtAsset
    ) external view returns (uint256);

    /**
     * @notice 根据偿还债务数量计算可获得的抵押品数量
     * @param debtAsset 清算人偿还的债务资产
     * @param collateralAsset 清算人获得的抵押资产
     * @param repayAmount 偿还债务数量
     * @return 可扣押的抵押品数量
     *
     * 计算大致逻辑：
     * debtValue = repayAmount * debtAssetPrice
     * seizeValue = debtValue * liquidationBonus
     * seizeAmount = seizeValue / collateralAssetPrice
     */
    function calculateSeizeAmount(
        address debtAsset,
        address collateralAsset,
        uint256 repayAmount
    ) external view returns (uint256);
}