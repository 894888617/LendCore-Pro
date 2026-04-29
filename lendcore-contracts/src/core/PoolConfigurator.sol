// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IPoolConfigurator} from "../interfaces/IPoolConfigurator.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title PoolConfigurator
 * @notice LendCore Pro 市场配置入口模块
 * @dev
 * PoolConfigurator 不直接保存市场配置，也不直接管理用户资金。
 *
 * 它的职责是：
 * 1. 作为管理员配置入口
 * 2. 校验调用者权限
 * 3. 把配置操作转发给 LendingPool
 *
 * 当前架构：
 * Admin -> PoolConfigurator -> LendingPool
 *
 * 这样做的好处：
 * - LendingPool 更专注于用户主流程
 * - 后台管理逻辑更清晰
 * - 后续可以把参数变更、Timelock、多签、治理流程接在 PoolConfigurator 前面
 */
contract PoolConfigurator is IPoolConfigurator, AccessControl {
    bytes32 public constant CONFIG_ADMIN_ROLE = keccak256("CONFIG_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @notice LendingPool 主合约地址
     */
    address public immutable lendingPool;

    /**
     * @notice 创建 PoolConfigurator
     * @param lendingPool_ LendingPool 地址
     * @param admin 管理员地址
     */
    constructor(address lendingPool_, address admin) {
        if (lendingPool_ == address(0) || admin == address(0)) {
            revert Errors.ZeroAddress();
        }

        lendingPool = lendingPool_;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    /**
     * @notice 初始化市场
     */
    function initMarket(
        address asset,
        DataTypes.MarketConfig calldata config
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        IPoolConfigurator(lendingPool).initMarket(asset, config);
    }

    /**
     * @notice 设置抵押因子
     */
    function setCollateralFactor(
        address asset,
        uint16 newFactorBps
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        IPoolConfigurator(lendingPool).setCollateralFactor(
            asset,
            newFactorBps
        );
    }

    /**
     * @notice 设置清算阈值
     */
    function setLiquidationThreshold(
        address asset,
        uint16 newThresholdBps
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        IPoolConfigurator(lendingPool).setLiquidationThreshold(
            asset,
            newThresholdBps
        );
    }

    /**
     * @notice 设置清算奖励
     */
    function setLiquidationBonus(
        address asset,
        uint16 newBonusBps
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        IPoolConfigurator(lendingPool).setLiquidationBonus(
            asset,
            newBonusBps
        );
    }

    /**
     * @notice 设置价格源地址
     */
    function setOracle(
        address asset,
        address oracle
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        IPoolConfigurator(lendingPool).setOracle(asset, oracle);
    }

    /**
     * @notice 设置利率模型地址
     */
    function setInterestRateModel(
        address asset,
        address model
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        IPoolConfigurator(lendingPool).setInterestRateModel(asset, model);
    }

    /**
     * @notice 设置借款开关
     */
    function setBorrowEnabled(
        address asset,
        bool enabled
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        IPoolConfigurator(lendingPool).setBorrowEnabled(asset, enabled);
    }

    /**
     * @notice 设置抵押开关
     */
    function setCollateralEnabled(
        address asset,
        bool enabled
    ) external onlyRole(CONFIG_ADMIN_ROLE) {
        IPoolConfigurator(lendingPool).setCollateralEnabled(asset, enabled);
    }

    /**
     * @notice 暂停协议
     */
    function pauseProtocol() external onlyRole(PAUSER_ROLE) {
        IPoolConfigurator(lendingPool).pauseProtocol();
    }

    /**
     * @notice 恢复协议
     */
    function unpauseProtocol() external onlyRole(PAUSER_ROLE) {
        IPoolConfigurator(lendingPool).unpauseProtocol();
    }
}