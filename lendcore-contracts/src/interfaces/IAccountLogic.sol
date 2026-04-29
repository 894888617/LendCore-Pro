// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAccountLogic
 * @notice LendCore Pro 用户账户风险计算接口
 * @dev
 * 这个接口不负责转账，也不负责修改状态。
 * 它只负责计算用户仓位风险。
 *
 * 核心概念：
 * 1. 总抵押价值
 * 2. 总债务价值
 * 3. 可借额度
 * 4. 健康因子
 */
interface IAccountLogic {
    /**
     * @notice 获取用户总抵押价值
     * @param user 用户地址
     * @return 用户所有启用抵押资产的总价值
     *
     * 说明：
     * - 需要读取用户 supplied 数量
     * - 需要读取资产价格
     * - 需要判断 useAsCollateral 是否开启
     */
    function getUserTotalCollateralValue(
        address user
    ) external view returns (uint256);

    /**
     * @notice 获取用户总债务价值
     * @param user 用户地址
     * @return 用户所有借款资产的总债务价值
     */
    function getUserTotalDebtValue(
        address user
    ) external view returns (uint256);

    /**
     * @notice 获取用户剩余可借额度
     * @param user 用户地址
     * @return 用户当前还可以借出的价值额度
     *
     * 计算大致逻辑：
     * 可借额度 = 抵押价值 * 抵押因子 - 当前债务价值
     */
    function getUserBorrowCapacity(
        address user
    ) external view returns (uint256);

    /**
     * @notice 获取用户健康因子
     * @param user 用户地址
     * @return 健康因子，WAD 精度，1e18 表示 1
     *
     * 业务含义：
     * - > 1e18：安全
     * - = 1e18：临界
     * - < 1e18：可被清算
     */
    function getHealthFactor(
        address user
    ) external view returns (uint256);

    /**
     * @notice 模拟用户借款后的健康因子
     * @param user 用户地址
     * @param asset 借款资产地址
     * @param amount 借款数量
     * @return 借款后的健康因子
     *
     * 使用场景：
     * - borrow 前先调用
     * - 确保借款后仓位仍然安全
     */
    function getHealthFactorAfterBorrow(
        address user,
        address asset,
        uint256 amount
    ) external view returns (uint256);

    /**
     * @notice 模拟用户提取资产后的健康因子
     * @param user 用户地址
     * @param asset 提取资产地址
     * @param amount 提取数量
     * @return 提取后的健康因子
     *
     * 使用场景：
     * - withdraw 前先调用
     * - 确保提取抵押品后不会变成危险仓位
     */
    function getHealthFactorAfterWithdraw(
        address user,
        address asset,
        uint256 amount
    ) external view returns (uint256);

    /**
     * @notice
     */
    function getHealthFactorAfterDisableCollateral(
        address user,
        address disabledAsset
    ) external view returns (uint256);

    function getAssetValue(
        address asset,
        uint256 amount
    ) external view returns (uint256);
}