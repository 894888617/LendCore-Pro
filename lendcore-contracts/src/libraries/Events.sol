// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Events
 * @notice LendCore Pro 协议统一事件定义
 * @dev
 * 事件的作用不只是给前端看。
 * 后续 Go 后端会监听这些事件，用来：
 * 1. 同步用户仓位
 * 2. 同步市场状态
 * 3. 生成风险快照
 * 4. 生成清算任务
 * 5. 做协议数据看板
 */
library Events {
    /**
     * @notice 用户存入资产
     * @param user 存款用户
     * @param asset 存入资产
     * @param amount 存入数量
     * @param useAsCollateral 是否启用为抵押
     */
    event Deposit(
        address indexed user,
        address indexed asset,
        uint256 amount,
        bool useAsCollateral
    );

    /**
     * @notice 用户提取资产
     * @param user 提取用户
     * @param asset 提取资产
     * @param amount 提取数量
     */
    event Withdraw(
        address indexed user,
        address indexed asset,
        uint256 amount
    );

    /**
     * @notice 用户借款
     * @param user 借款用户
     * @param asset 借款资产
     * @param amount 借款数量
     */
    event Borrow(
        address indexed user,
        address indexed asset,
        uint256 amount
    );

    /**
     * @notice 用户还款
     * @param user 还款用户
     * @param asset 还款资产
     * @param amount 实际还款数量
     */
    event Repay(
        address indexed user,
        address indexed asset,
        uint256 amount
    );

    /**
     * @notice 清算事件
     * @param liquidator 清算人
     * @param user 被清算用户
     * @param debtAsset 被偿还的债务资产
     * @param collateralAsset 被扣押的抵押资产
     * @param repayAmount 清算人偿还的债务数量
     * @param seizedCollateral 清算人获得的抵押品数量
     */
    event Liquidate(
        address indexed liquidator,
        address indexed user,
        address indexed debtAsset,
        address collateralAsset,
        uint256 repayAmount,
        uint256 seizedCollateral
    );

    /**
     * @notice 用户切换某资产是否作为抵押
     * @param user 用户地址
     * @param asset 资产地址
     * @param enabled 是否启用为抵押
     */
    event UseAsCollateralChanged(
        address indexed user,
        address indexed asset,
        bool enabled
    );

    /**
     * @notice 市场初始化
     * @param asset 被初始化的资产地址
     */
    event MarketInitialized(address indexed asset);

    /**
     * @notice 抵押因子更新
     * @param asset 资产地址
     * @param oldValue 旧值
     * @param newValue 新值
     */
    event CollateralFactorUpdated(
        address indexed asset,
        uint16 oldValue,
        uint16 newValue
    );

    /**
     * @notice 清算阈值更新
     * @param asset 资产地址
     * @param oldValue 旧值
     * @param newValue 新值
     */
    event LiquidationThresholdUpdated(
        address indexed asset,
        uint16 oldValue,
        uint16 newValue
    );

    /**
     * @notice 清算奖励更新
     * @param asset 资产地址
     * @param oldValue 旧值
     * @param newValue 新值
     */
    event LiquidationBonusUpdated(
        address indexed asset,
        uint16 oldValue,
        uint16 newValue
    );

    /**
     * @notice 价格源更新
     * @param asset 资产地址
     * @param oldOracle 旧价格源地址
     * @param newOracle 新价格源地址
     */
    event OracleUpdated(
        address indexed asset,
        address oldOracle,
        address newOracle
    );

    /**
     * @notice 利率模型更新
     * @param asset 资产地址
     * @param oldModel 旧利率模型地址
     * @param newModel 新利率模型地址
     */
    event InterestRateModelUpdated(
        address indexed asset,
        address oldModel,
        address newModel
    );

    /**
     * @notice 某资产借款开关更新
     * @param asset 资产地址
     * @param enabled 是否允许借款
     */
    event BorrowEnabledUpdated(address indexed asset, bool enabled);

    /**
     * @notice 某资产抵押开关更新
     * @param asset 资产地址
     * @param enabled 是否允许作为抵押
     */
    event CollateralEnabledUpdated(address indexed asset, bool enabled);

    /**
     * @notice 协议暂停
     */
    event ProtocolPaused();

    /**
     * @notice 协议恢复
     */
    event ProtocolUnpaused();
}