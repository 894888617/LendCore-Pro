// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DataTypes
 * @notice LendCore Pro 协议的公共数据结构库
 * @dev
 * 这个库只定义结构体和常量，不保存状态，不执行转账。
 * 这样做的好处是：
 * 1. 所有合约复用同一套数据结构
 * 2. 避免在多个合约中重复定义 struct
 * 3. 后续 Go 后端解析链上数据时，也能和这里的结构保持一致
 */
library DataTypes {
    /**
     * @notice BPS 精度，10000 表示 100%
     * @dev
     * 例如：
     * 7500 = 75%
     * 8000 = 80%
     * 10500 = 105%
     */
    uint256 internal constant BPS = 10_000;

    /**
     * @notice WAD 精度，1e18
     * @dev 常用于健康因子、利率、比例计算
     */
    uint256 internal constant WAD = 1e18;

    /**
     * @notice 价格精度，统一按 1e8 处理
     * @dev Chainlink 很多 USD 价格源默认是 8 位小数
     */
    uint256 internal constant PRICE_FEED_DECIMALS = 1e8;

    /**
     * @notice 市场配置
     * @dev
     * 每一个支持的资产都会有一份 MarketConfig。
     *
     * 举例：
     * WETH 可以作为抵押资产，但不一定允许被借出。
     * MockUSDC 可以被借出，但不一定允许作为抵押品。
     */
    struct MarketConfig {
        /**
         * @notice 该资产是否已被协议支持
         */
        bool isListed;

        /**
         * @notice 该资产是否可以作为抵押品
         */
        bool isCollateralEnabled;

        /**
         * @notice 该资产是否可以被借出
         */
        bool isBorrowEnabled;

        /**
         * @notice 抵押因子，决定最大可借额度
         * @dev
         * 例如 collateralFactorBps = 7500
         * 表示用户最多可以按抵押品价值的 75% 借款
         */
        uint16 collateralFactorBps;

        /**
         * @notice 清算阈值
         * @dev
         * 例如 liquidationThresholdBps = 8000
         * 表示当债务超过抵押价值的 80% 安全边界后，
         * 健康因子可能低于 1，进入可清算状态。
         */
        uint16 liquidationThresholdBps;

        /**
         * @notice 清算奖励
         * @dev
         * 例如 liquidationBonusBps = 10500
         * 表示清算人偿还 100 美元债务，
         * 可以拿到约 105 美元价值的抵押品。
         */
        uint16 liquidationBonusBps;

        /**
         * @notice token 自身精度
         * @dev
         * WETH 通常是 18
         * USDC 通常是 6
         */
        uint8 decimals;

        /**
         * @notice 该资产对应的价格源地址
         * @dev V1 可以先用 MockAggregator 或 OracleAdapter
         */
        address oracle;

        /**
         * @notice 利率模型地址
         * @dev 后续用于根据资金池利用率计算借款利率
         */
        address interestRateModel;
    }

    /**
     * @notice 市场运行状态
     * @dev
     * MarketConfig 是“静态配置”，MarketState 是“动态状态”。
     * 比如某资产池当前一共存了多少、借了多少。
     */
    struct MarketState {
        /**
         * @notice 市场总存入数量
         * @dev 按 token 原始 decimals 记录
         */
        uint256 totalSupply;

        /**
         * @notice 市场总借款数量
         * @dev 按 token 原始 decimals 记录
         */
        uint256 totalBorrow;

        /**
         * @notice 借款累计指数
         * @dev
         * 用于后续做利息累计。
         * V1 第一版可以先初始化为 1e18。
         */
        uint256 borrowIndex;

        /**
         * @notice 存款累计指数
         * @dev
         * V1 可以先预留，后续做存款收益时再启用。
         */
        uint256 supplyIndex;

        /**
         * @notice 上次结息时间戳
         * @dev 用 block.timestamp 记录
         */
        uint256 lastAccrualTimestamp;
    }

    /**
     * @notice 用户在某个资产市场中的仓位
     * @dev
     * mapping 设计通常是：
     * user => asset => UserReservePosition
     *
     * 比如：
     * 用户 A 在 WETH 市场 supplied = 1e18
     * 用户 A 在 MockUSDC 市场 borrowed = 1000e6
     */
    struct UserReservePosition {
        /**
         * @notice 用户存入的资产数量
         */
        uint256 supplied;

        /**
         * @notice 用户借出的资产债务数量
         */
        uint256 borrowed;

        /**
         * @notice 是否把该资产作为抵押品
         * @dev
         * 用户可以存入资产，但不一定启用为抵押。
         */
        bool useAsCollateral;

        /**
         * @notice 用户借款指数快照
         * @dev
         * 用于后续按 borrowIndex 计算利息。
         * V1 第一版可以先赋值但不深度使用。
         */
        uint256 borrowIndexSnapshot;
    }
}