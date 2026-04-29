// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IPriceOracleAdapter} from "../interfaces/IPriceOracleAdapter.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {LiquidationLogic} from "../logic/LiquidationLogic.sol";
import {IAccountLogic} from "../interfaces/IAccountLogic.sol";
import {AccountLogic} from "../logic/AccountLogic.sol";
import {PoolConfigurator} from "./PoolConfigurator.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {Events} from "../libraries/Events.sol";

/**
 * @title LendingPool
 * @notice LendCore Pro 借贷协议主合约
 * @dev
 * 这是协议的核心入口。
 *
 * 当前版本目标：
 * 1. 先搭建可编译、可扩展的主合约骨架
 * 2. 支持市场初始化
 * 3. 支持 deposit / withdraw / borrow / repay / liquidate 的基础流程
 * 4. 先预留健康因子、预言机、利率模型、真实清算计算
 *
 * 注意：
 * 当前版本是第一版骨架，不是最终生产版本。
 * 后续还需要补：
 * - AccountLogic 健康因子计算
 * - PriceOracleAdapter 价格读取
 * - InterestRateModel 利率累计
 * - LiquidationLogic 真实清算计算
 */
contract LendingPool is ILendingPool, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ============================================================
    // Roles
    // ============================================================

    /**
     * @notice 市场配置管理员
     * @dev 可以初始化市场、修改风险参数、修改 oracle、修改利率模型等。
     */
    bytes32 public constant CONFIG_ADMIN_ROLE = keccak256("CONFIG_ADMIN_ROLE");

    /**
     * @notice 暂停管理员
     * @dev 可以暂停或恢复协议。
     */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============================================================
    // Constants
    // ============================================================

    /**
     * @notice BPS 精度，10000 = 100%
     */
    uint256 internal constant BPS = 10_000;

    /**
     * @notice WAD 精度，1e18
     */
    uint256 internal constant WAD = 1e18;

    /**
     * @notice 单次最大清算比例，5000 = 50%
     * @dev V1 先固定为 50%，后续可改为市场参数。
     */
    uint16 internal constant MAX_LIQUIDATION_CLOSE_FACTOR_BPS = 5_000;

    /**
     * @notice 一年秒数，用于年化利率换算
     */
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    // ============================================================
    // Storage
    // ============================================================

    /**
     * @notice 市场配置
     * @dev asset => MarketConfig
     */
    mapping(address => DataTypes.MarketConfig) internal s_marketConfigs;

    /**
     * @notice 市场运行状态
     * @dev asset => MarketState
     */
    mapping(address => DataTypes.MarketState) internal s_marketStates;

    /**
     * @notice 用户仓位
     * @dev user => asset => position
     */
    mapping(address => mapping(address => DataTypes.UserReservePosition))
    internal s_userPositions;

    /**
     * @notice 快速判断市场是否已经上线
     */
    mapping(address => bool) internal s_isListedMarket;

    /**
     * @notice 已上线资产列表
     * @dev 用于前端、后端、AccountLogic 遍历市场。
     */
    address[] internal s_listedMarkets;

    /**
     * @notice 协议准备金地址
     * @dev V1 先保存地址，后续接 reserve factor 收益。
     */
    address internal s_treasury;

    /**
     * @notice 协议暂停状态
     */
    bool internal s_paused;

    /**
     * @notice 清算逻辑模块地址
     */
    address internal s_liquidationLogic;

    /**
     * @notice 账户风险计算模块地址
     */
    address internal s_accountLogic;

    /**
     * @notice 市场配置入口模块地址
     */
    address internal s_poolConfigurator;

    // ============================================================
    // Constructor
    // ============================================================

    /**
     * @notice 初始化 LendingPool
     * @param admin 管理员地址
     * @param treasury_ 协议准备金地址
     */
    constructor(address admin, address treasury_) {
        if (admin == address(0) || treasury_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIG_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        s_treasury = treasury_;
        s_liquidationLogic = address(
            new LiquidationLogic(MAX_LIQUIDATION_CLOSE_FACTOR_BPS)
        );

        s_accountLogic = address(new AccountLogic(address(this)));

        s_poolConfigurator = address(new PoolConfigurator(address(this), admin));

        _grantRole(CONFIG_ADMIN_ROLE, s_poolConfigurator);
        _grantRole(PAUSER_ROLE, s_poolConfigurator);
    }

    // ============================================================
    // Modifiers
    // ============================================================

    /**
     * @notice 校验资产市场已经上线
     */
    modifier onlyListedMarket(address asset) {
        if (!s_isListedMarket[asset]) {
            revert Errors.MarketNotListed(asset);
        }
        _;
    }

    /**
     * @notice 校验协议没有暂停
     */
    modifier whenNotPaused() {
        if (s_paused) {
            revert Errors.ProtocolPaused();
        }
        _;
    }

    /**
     * @notice 只允许 PoolConfigurator 调用
     */
    modifier onlyPoolConfigurator() {
        if (msg.sender != s_poolConfigurator) {
            revert Errors.NotPoolConfigurator(msg.sender);
        }
        _;
    }

    // ============================================================
    // Admin Functions
    // ============================================================

    /**
     * @notice 初始化一个资产市场
     * @param asset 资产地址
     * @param config 市场配置
     *
     * 业务说明：
     * - 一个资产只能初始化一次
     * - 初始化后可以作为抵押资产或借贷资产使用
     * - V1 中 WETH 可以配置为抵押资产，MockUSDC 可以配置为借贷资产
     */
    function initMarket(
        address asset,
        DataTypes.MarketConfig calldata config
    ) external onlyPoolConfigurator {
        if (asset == address(0)) {
            revert Errors.ZeroAddress();
        }

        if (s_isListedMarket[asset]) {
            revert Errors.MarketAlreadyListed(asset);
        }

        _validateMarketConfig(config);

        s_marketConfigs[asset] = config;

        s_marketStates[asset] = DataTypes.MarketState({
            totalSupply: 0,
            totalBorrow: 0,
            borrowIndex: WAD,
            supplyIndex: WAD,
            lastAccrualTimestamp: block.timestamp
        });

        s_isListedMarket[asset] = true;
        s_listedMarkets.push(asset);

        emit Events.MarketInitialized(asset);
    }

    /**
     * @notice 设置抵押因子
     * @param asset 资产地址
     * @param newFactorBps 新抵押因子
     */
    function setCollateralFactor(
        address asset,
        uint16 newFactorBps
    ) external onlyPoolConfigurator onlyListedMarket(asset) {
        DataTypes.MarketConfig storage cfg = s_marketConfigs[asset];

        if (
            newFactorBps > cfg.liquidationThresholdBps ||
            newFactorBps > BPS
        ) {
            revert Errors.InvalidCollateralFactor(newFactorBps);
        }

        uint16 oldValue = cfg.collateralFactorBps;
        cfg.collateralFactorBps = newFactorBps;

        emit Events.CollateralFactorUpdated(asset, oldValue, newFactorBps);
    }

    /**
     * @notice 设置清算阈值
     * @param asset 资产地址
     * @param newThresholdBps 新清算阈值
     */
    function setLiquidationThreshold(
        address asset,
        uint16 newThresholdBps
    ) external onlyPoolConfigurator onlyListedMarket(asset) {
        DataTypes.MarketConfig storage cfg = s_marketConfigs[asset];

        if (
            newThresholdBps < cfg.collateralFactorBps ||
            newThresholdBps > BPS
        ) {
            revert Errors.InvalidLiquidationThreshold(newThresholdBps);
        }

        uint16 oldValue = cfg.liquidationThresholdBps;
        cfg.liquidationThresholdBps = newThresholdBps;

        emit Events.LiquidationThresholdUpdated(
            asset,
            oldValue,
            newThresholdBps
        );
    }

    /**
     * @notice 设置清算奖励
     * @param asset 资产地址
     * @param newBonusBps 新清算奖励
     */
    function setLiquidationBonus(
        address asset,
        uint16 newBonusBps
    ) external onlyPoolConfigurator onlyListedMarket(asset) {
        if (newBonusBps < BPS) {
            revert Errors.InvalidLiquidationBonus(newBonusBps);
        }

        DataTypes.MarketConfig storage cfg = s_marketConfigs[asset];

        uint16 oldValue = cfg.liquidationBonusBps;
        cfg.liquidationBonusBps = newBonusBps;

        emit Events.LiquidationBonusUpdated(asset, oldValue, newBonusBps);
    }

    /**
     * @notice 设置价格源地址
     * @param asset 资产地址
     * @param oracle 新价格源地址
     */
    function setOracle(
        address asset,
        address oracle
    ) external onlyPoolConfigurator onlyListedMarket(asset) {
        if (oracle == address(0)) {
            revert Errors.InvalidOracle(oracle);
        }

        DataTypes.MarketConfig storage cfg = s_marketConfigs[asset];

        address oldOracle = cfg.oracle;
        cfg.oracle = oracle;

        emit Events.OracleUpdated(asset, oldOracle, oracle);
    }

    /**
     * @notice 设置利率模型地址
     * @param asset 资产地址
     * @param model 新利率模型地址
     */
    function setInterestRateModel(
        address asset,
        address model
    ) external onlyPoolConfigurator onlyListedMarket(asset) {
        if (model == address(0)) {
            revert Errors.InvalidInterestRateModel(model);
        }

        DataTypes.MarketConfig storage cfg = s_marketConfigs[asset];

        address oldModel = cfg.interestRateModel;
        cfg.interestRateModel = model;

        emit Events.InterestRateModelUpdated(asset, oldModel, model);
    }

    /**
     * @notice 设置某资产是否允许借款
     */
    function setBorrowEnabled(
        address asset,
        bool enabled
    ) external onlyPoolConfigurator onlyListedMarket(asset) {
        s_marketConfigs[asset].isBorrowEnabled = enabled;

        emit Events.BorrowEnabledUpdated(asset, enabled);
    }

    /**
     * @notice 设置某资产是否允许作为抵押
     */
    function setCollateralEnabled(
        address asset,
        bool enabled
    ) external onlyPoolConfigurator onlyListedMarket(asset) {
        s_marketConfigs[asset].isCollateralEnabled = enabled;

        emit Events.CollateralEnabledUpdated(asset, enabled);
    }

    /**
     * @notice 设置清算逻辑模块地址
     * @param newLiquidationLogic 新清算逻辑模块地址
     */
    function setLiquidationLogic(
        address newLiquidationLogic
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newLiquidationLogic == address(0)) {
            revert Errors.ZeroAddress();
        }

        s_liquidationLogic = newLiquidationLogic;
    }

    /**
     * @notice 设置账户风险计算模块地址
     * @param newAccountLogic 新账户逻辑模块地址
     */
    function setAccountLogic(
        address newAccountLogic
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAccountLogic == address(0)) {
            revert Errors.ZeroAddress();
        }

        s_accountLogic = newAccountLogic;
    }

    /**
     * @notice 设置新的 PoolConfigurator 地址
     * @param newPoolConfigurator 新配置器地址
     * @dev
     * 后续如果要升级配置模块，可以通过该函数替换。
     * 新配置器会获得 CONFIG_ADMIN_ROLE 和 PAUSER_ROLE。
     */
    function setPoolConfigurator(
        address newPoolConfigurator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPoolConfigurator == address(0)) {
            revert Errors.ZeroAddress();
        }

        s_poolConfigurator = newPoolConfigurator;

        _grantRole(CONFIG_ADMIN_ROLE, newPoolConfigurator);
        _grantRole(PAUSER_ROLE, newPoolConfigurator);
    }

    /**
     * @notice 暂停协议
     */
    function pauseProtocol() external onlyPoolConfigurator {
        s_paused = true;

        emit Events.ProtocolPaused();
    }

    /**
     * @notice 恢复协议
     */
    function unpauseProtocol() external onlyPoolConfigurator {
        s_paused = false;

        emit Events.ProtocolUnpaused();
    }

    // ============================================================
    // User Functions
    // ============================================================

    /**
     * @inheritdoc ILendingPool
     */
    function deposit(
        address asset,
        uint256 amount,
        bool useAsCollateral
    ) external nonReentrant whenNotPaused onlyListedMarket(asset) {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }

        DataTypes.MarketConfig memory cfg = s_marketConfigs[asset];

        if (!cfg.isListed) {
            revert Errors.MarketNotListed(asset);
        }

        if (useAsCollateral && !cfg.isCollateralEnabled) {
            revert Errors.MarketNotCollateralEnabled(asset);
        }

        _transferIn(asset, msg.sender, amount);

        DataTypes.UserReservePosition storage position = s_userPositions[
                        msg.sender
            ][asset];

        DataTypes.MarketState storage state = s_marketStates[asset];

        position.supplied += amount;

        if (useAsCollateral) {
            position.useAsCollateral = true;
        }

        state.totalSupply += amount;

        emit Events.Deposit(msg.sender, asset, amount, useAsCollateral);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function withdraw(
        address asset,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyListedMarket(asset) {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }

        DataTypes.UserReservePosition storage position = s_userPositions[
                        msg.sender
            ][asset];

        if (position.supplied < amount) {
            revert Errors.InsufficientSupplyBalance(
                msg.sender,
                asset,
                amount
            );
        }


        // 如果该资产正在作为抵押品，需要检查提取后健康因子是否仍然安全。
        if (position.useAsCollateral) {
            uint256 hfAfter = IAccountLogic(s_accountLogic)
                .getHealthFactorAfterWithdraw(msg.sender, asset, amount);

            if (hfAfter < WAD) {
                revert Errors.HealthFactorTooLow(msg.sender, hfAfter);
            }
        }

        position.supplied -= amount;
        s_marketStates[asset].totalSupply -= amount;

        _transferOut(asset, msg.sender, amount);

        emit Events.Withdraw(msg.sender, asset, amount);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function setUseAsCollateral(
        address asset,
        bool enabled
    ) external nonReentrant onlyListedMarket(asset) {
        DataTypes.UserReservePosition storage position = s_userPositions[
                        msg.sender
            ][asset];

        if (position.supplied == 0) {
            revert Errors.NoSupply(msg.sender, asset);
        }

        if (enabled) {
            if (!s_marketConfigs[asset].isCollateralEnabled) {
                revert Errors.MarketNotCollateralEnabled(asset);
            }
        } else {
            // 关闭抵押前，需要检查关闭后健康因子是否仍然安全。
            uint256 hfAfter = _getHealthFactorAfterDisableCollateral(
                msg.sender,
                asset
            );

            if (hfAfter < WAD) {
                revert Errors.HealthFactorTooLow(msg.sender, hfAfter);
            }
        }

        position.useAsCollateral = enabled;

        emit Events.UseAsCollateralChanged(msg.sender, asset, enabled);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function borrow(
        address asset,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyListedMarket(asset) {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }

        DataTypes.MarketConfig memory cfg = s_marketConfigs[asset];

        if (!cfg.isBorrowEnabled) {
            revert Errors.MarketNotBorrowable(asset);
        }

        _accrueInterest(asset);

        uint256 availableLiquidity = IERC20(asset).balanceOf(address(this));
        if (availableLiquidity < amount) {
            revert Errors.InsufficientLiquidity(
                asset,
                amount,
                availableLiquidity
            );
        }

        // 借款前必须检查借款后健康因子。
        uint256 borrowValue = IAccountLogic(s_accountLogic).getAssetValue(
            asset,
            amount
        );

        uint256 availableBorrowValue = IAccountLogic(s_accountLogic)
            .getUserBorrowCapacity(msg.sender);

        if (borrowValue > availableBorrowValue) {
            revert Errors.InsufficientBorrowCapacity(
                msg.sender,
                borrowValue,
                availableBorrowValue
            );
        }

        DataTypes.UserReservePosition storage position = s_userPositions[
                        msg.sender
            ][asset];

        DataTypes.MarketState storage state = s_marketStates[asset];

        uint256 currentDebt = _getCurrentUserDebt(msg.sender, asset);

        position.borrowed = currentDebt + amount;
        position.borrowIndexSnapshot = state.borrowIndex;

        state.totalBorrow += amount;

        _transferOut(asset, msg.sender, amount);

        emit Events.Borrow(msg.sender, asset, amount);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function repay(
        address asset,
        uint256 amount
    )
    external
    nonReentrant
    onlyListedMarket(asset)
    returns (uint256 actualRepaid)
    {
        if (amount == 0) {
            revert Errors.ZeroAmount();
        }

        _accrueInterest(asset);

        DataTypes.UserReservePosition storage position = s_userPositions[
                        msg.sender
            ][asset];

        uint256 currentDebt = _getCurrentUserDebt(msg.sender, asset);

        if (currentDebt == 0) {
            revert Errors.NoDebt(msg.sender, asset);
        }

        actualRepaid = amount > currentDebt ? currentDebt : amount;

        _transferIn(asset, msg.sender, actualRepaid);

        position.borrowed = currentDebt - actualRepaid;
        position.borrowIndexSnapshot = s_marketStates[asset].borrowIndex;
        s_marketStates[asset].totalBorrow -= actualRepaid;

        emit Events.Repay(msg.sender, asset, actualRepaid);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function liquidate(
        address user,
        address debtAsset,
        address collateralAsset,
        uint256 repayAmount
    )
    external
    nonReentrant
    whenNotPaused
    onlyListedMarket(debtAsset)
    onlyListedMarket(collateralAsset)
    {
        if (repayAmount == 0) {
            revert Errors.ZeroAmount();
        }

        _accrueInterest(debtAsset);

        // 清算前必须检查 user 的健康因子 < 1e18。
        uint256 healthFactor = IAccountLogic(s_accountLogic).getHealthFactor(user);

        if (healthFactor >= WAD) {
            revert Errors.PositionNotLiquidatable(user, healthFactor);
        }

        DataTypes.UserReservePosition storage debtPosition = s_userPositions[
                    user
            ][debtAsset];

        DataTypes.UserReservePosition
        storage collateralPosition = s_userPositions[user][
                    collateralAsset
            ];

        uint256 currentDebt = _getCurrentUserDebt(user, debtAsset);

        if (currentDebt == 0) {
            revert Errors.NoDebt(user, debtAsset);
        }

        uint256 maxClose = (currentDebt * MAX_LIQUIDATION_CLOSE_FACTOR_BPS) /
                    BPS;

        uint256 actualRepay = repayAmount > maxClose ? maxClose : repayAmount;

        DataTypes.MarketConfig memory debtCfg = s_marketConfigs[debtAsset];
        DataTypes.MarketConfig memory collateralCfg = s_marketConfigs[
                    collateralAsset
            ];

        // 清算计算
        uint256 seizedCollateral = LiquidationLogic(s_liquidationLogic)
            .calculateSeizeAmountWithConfig(
            collateralCfg.oracle,
            debtAsset,
            collateralAsset,
            actualRepay,
            debtCfg.decimals,
            collateralCfg.decimals,
            collateralCfg.liquidationBonusBps
        );

        if (collateralPosition.supplied < seizedCollateral) {
            seizedCollateral = collateralPosition.supplied;
        }

        _transferIn(debtAsset, msg.sender, actualRepay);

        debtPosition.borrowed = currentDebt - actualRepay;
        debtPosition.borrowIndexSnapshot = s_marketStates[debtAsset]
            .borrowIndex;

        collateralPosition.supplied -= seizedCollateral;

        s_marketStates[debtAsset].totalBorrow -= actualRepay;

        _transferOut(collateralAsset, msg.sender, seizedCollateral);

        emit Events.Liquidate(
            msg.sender,
            user,
            debtAsset,
            collateralAsset,
            actualRepay,
            seizedCollateral
        );
    }

    // ============================================================
    // View Functions
    // ============================================================

    /**
     * @inheritdoc ILendingPool
     */
    function getUserPosition(
        address user,
        address asset
    ) external view returns (DataTypes.UserReservePosition memory) {
        return s_userPositions[user][asset];
    }

    /**
     * @inheritdoc ILendingPool
     */
    function getMarketConfig(
        address asset
    ) external view returns (DataTypes.MarketConfig memory) {
        return s_marketConfigs[asset];
    }

    /**
     * @inheritdoc ILendingPool
     */
    function getMarketState(
        address asset
    ) external view returns (DataTypes.MarketState memory) {
        return s_marketStates[asset];
    }

    /**
     * @inheritdoc ILendingPool
     */
    function getListedMarkets() external view returns (address[] memory) {
        return s_listedMarkets;
    }

    /**
     * @notice 查询用户总抵押价值
     * @param user 用户地址
     * @return collateralValue 用户总抵押价值，统一为 1e8 USD 精度
     */
    function getUserTotalCollateralValue(
        address user
    ) external view returns (uint256 collateralValue) {
        return IAccountLogic(s_accountLogic).getUserTotalCollateralValue(user);
    }

    /**
     * @notice 查询用户总债务价值
     * @param user 用户地址
     * @return debtValue 用户总债务价值，统一为 1e8 USD 精度
     */
    function getUserTotalDebtValue(
        address user
    ) external view returns (uint256 debtValue) {
        return IAccountLogic(s_accountLogic).getUserTotalDebtValue(user);
    }

    /**
     * @notice 查询用户当前可借额度
     * @param user 用户地址
     * @return availableBorrowValue 当前剩余可借价值，统一为 1e8 USD 精度
     */
    function getAvailableBorrowValue(
        address user
    ) external view returns (uint256 availableBorrowValue) {
        return IAccountLogic(s_accountLogic).getUserBorrowCapacity(user);
    }

    /**
     * @notice 查询用户健康因子
     * @param user 用户地址
     * @return healthFactor 健康因子，1e18 表示 1
     */
    function getHealthFactor(
        address user
    ) external view returns (uint256 healthFactor) {
        return IAccountLogic(s_accountLogic).getHealthFactor(user);
    }

    /**
     * @inheritdoc ILendingPool
     */
    function isPaused() external view returns (bool) {
        return s_paused;
    }

    /**
     * @notice 查询用户某资产当前债务
     * @dev 当前债务包含根据 borrowIndex 计算出来的利息。
     * @param user 用户地址
     * @param asset 借款资产地址
     * @return currentDebt 当前债务数量
     */
    function getCurrentDebt(
        address user,
        address asset
    ) external view returns (uint256 currentDebt) {
        return _getCurrentUserDebt(user, asset);
    }

    /**
     * @notice 查询当前账户风险计算模块地址
     */
    function getAccountLogic() external view returns (address) {
        return s_accountLogic;
    }

    /**
     * @notice 查询当前 PoolConfigurator 地址
     */
    function getPoolConfigurator() external view returns (address) {
        return s_poolConfigurator;
    }

    // ============================================================
    // Internal Functions
    // ============================================================

    /**
     * @notice 校验市场配置是否合法
     */
    function _validateMarketConfig(
        DataTypes.MarketConfig calldata config
    ) internal pure {
        if (config.oracle == address(0)) {
            revert Errors.InvalidOracle(config.oracle);
        }

        if (config.interestRateModel == address(0)) {
            revert Errors.InvalidInterestRateModel(config.interestRateModel);
        }

        if (
            config.collateralFactorBps > config.liquidationThresholdBps ||
            config.collateralFactorBps > BPS
        ) {
            revert Errors.InvalidCollateralFactor(config.collateralFactorBps);
        }

        if (config.liquidationThresholdBps > BPS) {
            revert Errors.InvalidLiquidationThreshold(
                config.liquidationThresholdBps
            );
        }

        if (config.liquidationBonusBps < BPS) {
            revert Errors.InvalidLiquidationBonus(config.liquidationBonusBps);
        }
    }

    /**
     * @notice 从用户转入 token
     */
    function _transferIn(address asset, address from, uint256 amount) internal {
        IERC20(asset).safeTransferFrom(from, address(this), amount);
    }

    /**
     * @notice 从协议转出 token
     */
    function _transferOut(address asset, address to, uint256 amount) internal {
        IERC20(asset).safeTransfer(to, amount);
    }

    /**
     * @notice 计提某资产市场的借款利息
     * @dev
     * 逻辑：
     * 1. 根据当前时间计算距离上次结息经过了多少秒
     * 2. 从利率模型读取当前借款年化利率
     * 3. 计算这段时间产生的利息因子
     * 4. 更新 borrowIndex
     * 5. 更新 totalBorrow
     *
     * 注意：
     * - 这里是 V1 简化版单利模型
     * - 后续可以升级为更精细的指数累计模型
     */
    function _accrueInterest(address asset) internal {
        DataTypes.MarketState storage state = s_marketStates[asset];

        uint256 currentTimestamp = block.timestamp;

        if (state.totalBorrow == 0) {
            state.lastAccrualTimestamp = currentTimestamp;
            return;
        }

        uint256 oldTimestamp = state.lastAccrualTimestamp;
        uint256 elapsed = currentTimestamp - oldTimestamp;

        if (elapsed == 0) {
            return;
        }

        uint256 oldBorrowIndex = state.borrowIndex;
        uint256 newBorrowIndex = _getProjectedBorrowIndex(asset);

        state.borrowIndex = newBorrowIndex;

        state.totalBorrow =
            (state.totalBorrow * newBorrowIndex) /
            oldBorrowIndex;

        state.lastAccrualTimestamp = currentTimestamp;
    }

    /**
     * @notice 计算某市场当前应该达到的 borrowIndex
     * @dev
     * 这是一个 view 函数，不修改状态。
     *
     * 如果当前时间已经晚于 lastAccrualTimestamp，
     * 它会基于利率模型计算“理论上的最新 borrowIndex”。
     */
    function _getProjectedBorrowIndex(
        address asset
    ) internal view returns (uint256) {
        DataTypes.MarketState memory state = s_marketStates[asset];

        if (state.totalBorrow == 0) {
            return state.borrowIndex;
        }

        uint256 currentTimestamp = block.timestamp;
        uint256 elapsed = currentTimestamp - state.lastAccrualTimestamp;

        if (elapsed == 0) {
            return state.borrowIndex;
        }

        DataTypes.MarketConfig memory cfg = s_marketConfigs[asset];

        uint256 totalLiquidity = IERC20(asset).balanceOf(address(this)) +
                        state.totalBorrow;

        uint256 borrowRate = IInterestRateModel(cfg.interestRateModel)
            .getBorrowRate(asset, totalLiquidity, state.totalBorrow);

        uint256 interestFactor = (borrowRate * elapsed) / SECONDS_PER_YEAR;

        return (state.borrowIndex * (WAD + interestFactor)) / WAD;
    }

    /**
     * @notice 获取用户当前债务
     * @dev
     * 用户 storage 中的 borrowed 可以理解为上一次交互后的债务快照。
     * 当前债务需要根据 borrowIndex 变化重新换算。
     */
    function _getCurrentUserDebt(
        address user,
        address asset
    ) internal view returns (uint256) {
        DataTypes.UserReservePosition memory position = s_userPositions[user][
                    asset
            ];

        if (position.borrowed == 0) {
            return 0;
        }

        uint256 snapshot = position.borrowIndexSnapshot;

        if (snapshot == 0) {
            return position.borrowed;
        }

        uint256 currentBorrowIndex = _getProjectedBorrowIndex(asset);

        return (position.borrowed * currentBorrowIndex) / snapshot;
    }

    /**
     * @notice 将 token 数量换算成 USD 价值
     * @dev
     * 返回值统一使用 1e8 USD 精度。
     *
     * 例如：
     * WETH decimals = 18
     * amount = 1e18
     * price = 3000e8
     * value = 3000e8
     */
    function _assetAmountToUsdValue(
        address asset,
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        DataTypes.MarketConfig memory cfg = s_marketConfigs[asset];

        (uint256 price, ) = IPriceOracleAdapter(cfg.oracle).getAssetPrice(
            asset
        );

        if (price == 0) {
            revert Errors.InvalidPrice(asset);
        }

        return (amount * price) / (10 ** cfg.decimals);
    }

    /**
     * @notice 获取用户总债务价值
     * @dev
     * 返回值为 1e8 USD 精度。
     */
    function _getUserTotalDebtValue(
        address user
    ) internal view returns (uint256 totalDebtValue) {
        uint256 len = s_listedMarkets.length;

        for (uint256 i = 0; i < len; i++) {
            address asset = s_listedMarkets[i];

            uint256 currentDebt = _getCurrentUserDebt(user, asset);

            if (currentDebt == 0) {
                continue;
            }

            uint256 value = _assetAmountToUsdValue(asset, currentDebt);

            totalDebtValue += value;
        }
    }


    /**
     * @notice 模拟关闭某资产抵押后的健康因子
     */
    function _getHealthFactorAfterDisableCollateral(
        address user,
        address disabledAsset
    ) internal view returns (uint256) {
        uint256 debtValue = _getUserTotalDebtValue(user);

        if (debtValue == 0) {
            return type(uint256).max;
        }

        uint256 adjustedCollateralValue = 0;
        uint256 len = s_listedMarkets.length;

        for (uint256 i = 0; i < len; i++) {
            address asset = s_listedMarkets[i];

            if (asset == disabledAsset) {
                continue;
            }

            DataTypes.UserReservePosition memory position = s_userPositions[
                        user
                ][asset];

            if (!position.useAsCollateral || position.supplied == 0) {
                continue;
            }

            DataTypes.MarketConfig memory cfg = s_marketConfigs[asset];

            uint256 value = _assetAmountToUsdValue(asset, position.supplied);

            adjustedCollateralValue +=
                (value * cfg.liquidationThresholdBps) /
                BPS;
        }

        return (adjustedCollateralValue * WAD) / debtValue;
    }

}