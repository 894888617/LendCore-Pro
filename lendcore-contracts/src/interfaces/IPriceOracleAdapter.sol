// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPriceOracleAdapter
 * @notice LendCore Pro 价格预言机适配接口
 * @dev
 * 协议不应该在 LendingPool 里直接写死 Chainlink 调用。
 * 所以用 OracleAdapter 做一层封装。
 *
 * 好处：
 * 1. 统一价格精度
 * 2. 统一检查价格是否有效
 * 3. 未来可以替换价格源
 */
interface IPriceOracleAdapter {
    /**
     * @notice 获取资产价格
     * @param asset 资产地址
     * @return price 资产价格，统一精度
     * @return updatedAt 价格更新时间
     *
     * V1 建议：
     * - price 使用 1e8 精度
     * - updatedAt 用于检查价格是否过期
     */
    function getAssetPrice(
        address asset
    ) external view returns (uint256 price, uint256 updatedAt);

    /**
     * @notice 检查资产价格是否有效
     * @param asset 资产地址
     * @return true 表示价格有效
     *
     * 有效条件通常包括：
     * - price > 0
     * - updatedAt 不为 0
     * - updatedAt 没有超过最大过期时间
     */
    function isPriceValid(
        address asset
    ) external view returns (bool);

    /**
     * @notice 获取价格精度
     * @return 价格精度小数位
     *
     * V1 约定返回 8。
     */
    function getPriceDecimals() external pure returns (uint8);
}