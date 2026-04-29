// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Errors
 * @notice LendCore Pro 协议统一错误定义
 * @dev
 * 使用 custom error 的好处：
 * 1. 比 require 字符串更省 gas
 * 2. 错误类型更清晰
 * 3. 测试时可以精确断言某个错误
 */
library Errors {
    /**
     * @notice 地址不能为 0
     */
    error ZeroAddress();

    /**
     * @notice 金额不能为 0
     */
    error ZeroAmount();

    /**
     * @notice 市场未上线
     * @param asset 资产地址
     */
    error MarketNotListed(address asset);

    /**
     * @notice 市场已经上线，不能重复初始化
     * @param asset 资产地址
     */
    error MarketAlreadyListed(address asset);

    /**
     * @notice 该市场不允许借款
     * @param asset 资产地址
     */
    error MarketNotBorrowable(address asset);

    /**
     * @notice 该市场不允许作为抵押品
     * @param asset 资产地址
     */
    error MarketNotCollateralEnabled(address asset);

    /**
     * @notice 协议已经暂停
     */
    error ProtocolPaused();

    /**
     * @notice 用户存款余额不足
     * @param user 用户地址
     * @param asset 资产地址
     * @param amount 本次尝试提取的数量
     */
    error InsufficientSupplyBalance(address user, address asset, uint256 amount);

    /**
     * @notice 池子流动性不足
     * @param asset 资产地址
     * @param requested 请求借出的数量
     * @param available 当前池子可用余额
     */
    error InsufficientLiquidity(address asset, uint256 requested, uint256 available);

    /**
     * @notice 健康因子过低
     * @param user 用户地址
     * @param healthFactor 当前或模拟后的健康因子
     */
    error HealthFactorTooLow(address user, uint256 healthFactor);

    /**
     * @notice 仓位不可清算
     * @param user 被检查用户
     * @param healthFactor 当前健康因子
     */
    error PositionNotLiquidatable(address user, uint256 healthFactor);

    /**
     * @notice 抵押因子配置非法
     * @param value 配置值
     */
    error InvalidCollateralFactor(uint256 value);

    /**
     * @notice 清算阈值配置非法
     * @param value 配置值
     */
    error InvalidLiquidationThreshold(uint256 value);

    /**
     * @notice 清算奖励配置非法
     * @param value 配置值
     */
    error InvalidLiquidationBonus(uint256 value);

    /**
     * @notice 价格源地址非法
     * @param oracle 价格源地址
     */
    error InvalidOracle(address oracle);

    /**
     * @notice 利率模型地址非法
     * @param model 利率模型地址
     */
    error InvalidInterestRateModel(address model);

    /**
     * @notice ERC20 转账失败
     * @param asset 资产地址
     * @param from 转出地址
     * @param to 转入地址
     * @param amount 转账数量
     */
    error TransferFailed(address asset, address from, address to, uint256 amount);

    /**
     * @notice 用户在该资产上没有债务
     * @param user 用户地址
     * @param asset 资产地址
     */
    error NoDebt(address user, address asset);

    /**
     * @notice 用户在该资产上没有存款
     * @param user 用户地址
     * @param asset 资产地址
     */
    error NoSupply(address user, address asset);

    /**
     * @notice 价格无效
     * @param asset 资产地址
     */
    error InvalidPrice(address asset);

    /**
     * @notice 借款额度不足
     * @param user 用户地址
     * @param requestedValue 请求借款价值
     * @param availableValue 可用借款价值
     */
    error InsufficientBorrowCapacity(
        address user,
        uint256 requestedValue,
        uint256 availableValue
    );

    /**
     * @notice 价格源未配置
     * @param asset 资产地址
     */
    error PriceFeedNotSet(address asset);

    /**
     * @notice 价格过期
     * @param asset 资产地址
     * @param updatedAt 价格更新时间
     */
    error StalePrice(address asset, uint256 updatedAt);

    /**
     * @notice 价格源返回轮次异常
     * @param asset 资产地址
     */
    error InvalidPriceRound(address asset);

    /**
     * @notice 调用者不是 PoolConfigurator
     * @param caller 调用者地址
     */
    error NotPoolConfigurator(address caller);
}