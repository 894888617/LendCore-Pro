// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataTypes} from "../libraries/DataTypes.sol";

/**
 * @title IPoolConfigurator
 * @notice LendCore Pro 市场配置接口
 * @dev
 * 这个接口主要给管理员使用。
 *
 * 它负责：
 * 1. 初始化资产市场
 * 2. 修改抵押因子
 * 3. 修改清算阈值
 * 4. 修改清算奖励
 * 5. 修改预言机地址
 * 6. 修改利率模型地址
 * 7. 开启/关闭借款和抵押功能
 * 8. 暂停/恢复协议
 */
interface IPoolConfigurator {
    /**
     * @notice 初始化一个资产市场
     * @param asset 资产地址
     * @param config 市场配置
     *
     * 业务说明：
     * - 一个资产只能初始化一次
     * - 初始化后，该资产才可以被 deposit / borrow 等函数使用
     */
    function initMarket(
        address asset,
        DataTypes.MarketConfig calldata config
    ) external;

    /**
     * @notice 设置抵押因子
     * @param asset 资产地址
     * @param newFactorBps 新抵押因子，BPS 精度
     *
     * 例如：
     * 7500 = 75%
     */
    function setCollateralFactor(
        address asset,
        uint16 newFactorBps
    ) external;

    /**
     * @notice 设置清算阈值
     * @param asset 资产地址
     * @param newThresholdBps 新清算阈值，BPS 精度
     *
     * 例如：
     * 8000 = 80%
     */
    function setLiquidationThreshold(
        address asset,
        uint16 newThresholdBps
    ) external;

    /**
     * @notice 设置清算奖励
     * @param asset 资产地址
     * @param newBonusBps 新清算奖励，BPS 精度
     *
     * 例如：
     * 10500 = 清算人获得 105% 抵押品价值
     */
    function setLiquidationBonus(
        address asset,
        uint16 newBonusBps
    ) external;

    /**
     * @notice 设置资产价格源
     * @param asset 资产地址
     * @param oracle 新预言机地址
     */
    function setOracle(address asset, address oracle) external;

    /**
     * @notice 设置利率模型
     * @param asset 资产地址
     * @param model 新利率模型地址
     */
    function setInterestRateModel(address asset, address model) external;

    /**
     * @notice 设置某资产是否允许借款
     * @param asset 资产地址
     * @param enabled 是否开启借款
     */
    function setBorrowEnabled(address asset, bool enabled) external;

    /**
     * @notice 设置某资产是否允许作为抵押品
     * @param asset 资产地址
     * @param enabled 是否开启抵押
     */
    function setCollateralEnabled(address asset, bool enabled) external;

    /**
     * @notice 暂停协议
     */
    function pauseProtocol() external;

    /**
     * @notice 恢复协议
     */
    function unpauseProtocol() external;
}