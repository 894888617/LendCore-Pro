// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataTypes} from "../libraries/DataTypes.sol";

/**
 * @title ILendingPool
 * @notice LendCore Pro 借贷池主入口接口
 * @dev
 * LendingPool 是用户最主要交互的合约。
 *
 * 用户通过它完成：
 * 1. 存入抵押品
 * 2. 提取资产
 * 3. 借款
 * 4. 还款
 * 5. 清算
 *
 * 后续 Go 后端和前端也会主要围绕这个接口工作。
 */
interface ILendingPool {
    /**
     * @notice 存入资产
     * @param asset 存入资产地址
     * @param amount 存入数量
     * @param useAsCollateral 是否把该资产作为抵押
     *
     * 业务说明：
     * - 用户需要先 approve LendingPool
     * - 协议会从用户钱包转入 asset
     * - 如果 useAsCollateral=true，该资产会参与借款额度计算
     */
    function deposit(
        address asset,
        uint256 amount,
        bool useAsCollateral
    ) external;

    /**
     * @notice 提取资产
     * @param asset 提取资产地址
     * @param amount 提取数量
     *
     * 业务说明：
     * - 用户只能提取自己存入的资产
     * - 如果该资产正在作为抵押品，提取后必须保证健康因子安全
     */
    function withdraw(address asset, uint256 amount) external;

    /**
     * @notice 设置某资产是否作为抵押品
     * @param asset 资产地址
     * @param enabled 是否启用为抵押
     *
     * 业务说明：
     * - 用户可以存入资产但不启用为抵押
     * - 如果关闭抵押会导致健康因子过低，则不能关闭
     */
    function setUseAsCollateral(address asset, bool enabled) external;

    /**
     * @notice 借出资产
     * @param asset 借款资产地址
     * @param amount 借款数量
     *
     * 业务说明：
     * - 用户必须有足够抵押品
     * - 借款后健康因子必须保持安全
     */
    function borrow(address asset, uint256 amount) external;

    /**
     * @notice 偿还债务
     * @param asset 偿还资产地址
     * @param amount 计划还款数量
     * @return actualRepaid 实际偿还数量
     *
     * 业务说明：
     * - 如果 amount 大于当前债务，只还实际债务数量
     * - 用户需要先 approve LendingPool
     */
    function repay(address asset, uint256 amount)
    external
    returns (uint256 actualRepaid);

    /**
     * @notice 清算高风险账户
     * @param user 被清算用户
     * @param debtAsset 清算人代还的债务资产
     * @param collateralAsset 清算人获得的抵押资产
     * @param repayAmount 清算人希望偿还的债务数量
     *
     * 业务说明：
     * - 只有当 user 健康因子低于 1 时才能清算
     * - 清算人偿还债务后，会获得带折扣/奖励的抵押品
     */
    function liquidate(
        address user,
        address debtAsset,
        address collateralAsset,
        uint256 repayAmount
    ) external;

    /**
     * @notice 查询用户在某资产上的仓位
     * @param user 用户地址
     * @param asset 资产地址
     * @return 用户仓位结构体
     */
    function getUserPosition(address user, address asset)
    external
    view
    returns (DataTypes.UserReservePosition memory);

    /**
     * @notice 查询某资产市场配置
     * @param asset 资产地址
     * @return 市场配置结构体
     */
    function getMarketConfig(address asset)
    external
    view
    returns (DataTypes.MarketConfig memory);

    /**
     * @notice 查询某资产市场运行状态
     * @param asset 资产地址
     * @return 市场状态结构体
     */
    function getMarketState(address asset)
    external
    view
    returns (DataTypes.MarketState memory);

    /**
     * @notice 查询所有已上线市场
     * @return 已上线资产地址数组
     */
    function getListedMarkets() external view returns (address[] memory);

    /**
     * @notice 查询协议是否暂停
     * @return true 表示暂停，false 表示正常
     */
    function isPaused() external view returns (bool);
}