// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccountLogic} from "../interfaces/IAccountLogic.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IPriceOracleAdapter} from "../interfaces/IPriceOracleAdapter.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title AccountLogic
 * @notice LendCore Pro 用户账户风险计算模块
 * @dev
 * 该模块只负责计算，不负责：
 * - 资产转账
 * - 修改用户仓位
 * - 修改市场状态
 *
 * LendingPool 负责状态修改和资金转移；
 * AccountLogic 负责读取 LendingPool 的 view 数据并计算风险指标。
 */
contract AccountLogic is IAccountLogic {
    uint256 public constant BPS = 10_000;
    uint256 public constant WAD = 1e18;

    address public immutable lendingPool;

    constructor(address lendingPool_) {
        if (lendingPool_ == address(0)) {
            revert Errors.ZeroAddress();
        }

        lendingPool = lendingPool_;
    }

    /**
     * @notice 获取用户总抵押价值
     * @dev 只统计 useAsCollateral = true 的资产，返回 1e8 USD 精度
     */
    function getUserTotalCollateralValue(
        address user
    ) external view returns (uint256 totalCollateralValue) {
        address[] memory markets = ILendingPool(lendingPool).getListedMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            address asset = markets[i];

            DataTypes.UserReservePosition memory position = ILendingPool(
                lendingPool
            ).getUserPosition(user, asset);

            if (!position.useAsCollateral || position.supplied == 0) {
                continue;
            }

            totalCollateralValue += _assetAmountToUsdValue(
                asset,
                position.supplied
            );
        }
    }

    /**
     * @notice 获取用户总债务价值
     * @dev 债务使用 getCurrentDebt，包含利息，返回 1e8 USD 精度
     */
    function getUserTotalDebtValue(
        address user
    ) public view returns (uint256 totalDebtValue) {
        address[] memory markets = ILendingPool(lendingPool).getListedMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            address asset = markets[i];

            uint256 currentDebt = ILendingPool(lendingPool).getCurrentDebt(
                user,
                asset
            );

            if (currentDebt == 0) {
                continue;
            }

            totalDebtValue += _assetAmountToUsdValue(asset, currentDebt);
        }
    }

    /**
     * @notice 获取用户剩余可借额度
     * @dev 可借额度 = 按 collateralFactor 加权后的抵押价值 - 当前债务价值
     */
    function getUserBorrowCapacity(
        address user
    ) external view returns (uint256) {
        uint256 borrowableCollateralValue = _getUserBorrowableCollateralValue(
            user
        );

        uint256 debtValue = getUserTotalDebtValue(user);

        if (borrowableCollateralValue <= debtValue) {
            return 0;
        }

        return borrowableCollateralValue - debtValue;
    }

    /**
     * @notice 获取用户健康因子
     * @dev healthFactor = 清算阈值加权抵押价值 * 1e18 / 总债务价值
     */
    function getHealthFactor(address user) public view returns (uint256) {
        uint256 debtValue = getUserTotalDebtValue(user);

        if (debtValue == 0) {
            return type(uint256).max;
        }

        uint256 adjustedCollateralValue = _getUserLiquidationAdjustedCollateralValue(
            user
        );

        return (adjustedCollateralValue * WAD) / debtValue;
    }

    /**
     * @notice 模拟借款后的健康因子
     */
    function getHealthFactorAfterBorrow(
        address user,
        address asset,
        uint256 amount
    ) external view returns (uint256) {
        uint256 debtValue = getUserTotalDebtValue(user);
        uint256 borrowValue = _assetAmountToUsdValue(asset, amount);

        uint256 newDebtValue = debtValue + borrowValue;

        if (newDebtValue == 0) {
            return type(uint256).max;
        }

        uint256 adjustedCollateralValue = _getUserLiquidationAdjustedCollateralValue(
            user
        );

        return (adjustedCollateralValue * WAD) / newDebtValue;
    }

    /**
     * @notice 模拟提取抵押品后的健康因子
     */
    function getHealthFactorAfterWithdraw(
        address user,
        address asset,
        uint256 amount
    ) external view returns (uint256) {
        uint256 debtValue = getUserTotalDebtValue(user);

        if (debtValue == 0) {
            return type(uint256).max;
        }

        uint256 adjustedCollateralValue;
        address[] memory markets = ILendingPool(lendingPool).getListedMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            address currentAsset = markets[i];

            DataTypes.UserReservePosition memory position = ILendingPool(
                lendingPool
            ).getUserPosition(user, currentAsset);

            if (!position.useAsCollateral || position.supplied == 0) {
                continue;
            }

            uint256 suppliedAmount = position.supplied;

            if (currentAsset == asset) {
                suppliedAmount = amount >= suppliedAmount
                    ? 0
                    : suppliedAmount - amount;
            }

            if (suppliedAmount == 0) {
                continue;
            }

            DataTypes.MarketConfig memory cfg = ILendingPool(lendingPool)
                .getMarketConfig(currentAsset);

            uint256 value = _assetAmountToUsdValue(
                currentAsset,
                suppliedAmount
            );

            adjustedCollateralValue +=
                (value * cfg.liquidationThresholdBps) /
                BPS;
        }

        return (adjustedCollateralValue * WAD) / debtValue;
    }

    /**
     * @notice 模拟关闭某资产抵押后的健康因子
     */
    function getHealthFactorAfterDisableCollateral(
        address user,
        address disabledAsset
    ) external view returns (uint256) {
        uint256 debtValue = getUserTotalDebtValue(user);

        if (debtValue == 0) {
            return type(uint256).max;
        }

        uint256 adjustedCollateralValue;
        address[] memory markets = ILendingPool(lendingPool).getListedMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            address asset = markets[i];

            if (asset == disabledAsset) {
                continue;
            }

            DataTypes.UserReservePosition memory position = ILendingPool(
                lendingPool
            ).getUserPosition(user, asset);

            if (!position.useAsCollateral || position.supplied == 0) {
                continue;
            }

            DataTypes.MarketConfig memory cfg = ILendingPool(lendingPool)
                .getMarketConfig(asset);

            uint256 value = _assetAmountToUsdValue(asset, position.supplied);

            adjustedCollateralValue +=
                (value * cfg.liquidationThresholdBps) /
                BPS;
        }

        return (adjustedCollateralValue * WAD) / debtValue;
    }

    /**
     * @notice 将某资产数量换算成 USD 价值
     * @dev 返回值为 1e8 USD 精度
     * @param asset 资产地址
     * @param amount token 数量
     */
    function getAssetValue(
        address asset,
        uint256 amount
    ) external view returns (uint256) {
        return _assetAmountToUsdValue(asset, amount);
    }

    /**
     * @notice 获取按 collateralFactor 加权后的抵押价值
     */
    function _getUserBorrowableCollateralValue(
        address user
    ) internal view returns (uint256 borrowableCollateralValue) {
        address[] memory markets = ILendingPool(lendingPool).getListedMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            address asset = markets[i];

            DataTypes.UserReservePosition memory position = ILendingPool(
                lendingPool
            ).getUserPosition(user, asset);

            if (!position.useAsCollateral || position.supplied == 0) {
                continue;
            }

            DataTypes.MarketConfig memory cfg = ILendingPool(lendingPool)
                .getMarketConfig(asset);

            uint256 value = _assetAmountToUsdValue(asset, position.supplied);

            borrowableCollateralValue +=
                (value * cfg.collateralFactorBps) /
                BPS;
        }
    }

    /**
     * @notice 获取按 liquidationThreshold 加权后的抵押价值
     */
    function _getUserLiquidationAdjustedCollateralValue(
        address user
    ) internal view returns (uint256 adjustedCollateralValue) {
        address[] memory markets = ILendingPool(lendingPool).getListedMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            address asset = markets[i];

            DataTypes.UserReservePosition memory position = ILendingPool(
                lendingPool
            ).getUserPosition(user, asset);

            if (!position.useAsCollateral || position.supplied == 0) {
                continue;
            }

            DataTypes.MarketConfig memory cfg = ILendingPool(lendingPool)
                .getMarketConfig(asset);

            uint256 value = _assetAmountToUsdValue(asset, position.supplied);

            adjustedCollateralValue +=
                (value * cfg.liquidationThresholdBps) /
                BPS;
        }
    }

    /**
     * @notice 将 token 数量换算成 USD 价值，返回 1e8 精度
     */
    function _assetAmountToUsdValue(
        address asset,
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        DataTypes.MarketConfig memory cfg = ILendingPool(lendingPool)
            .getMarketConfig(asset);

        (uint256 price, ) = IPriceOracleAdapter(cfg.oracle).getAssetPrice(
            asset
        );

        if (price == 0) {
            revert Errors.InvalidPrice(asset);
        }

        return (amount * price) / (10 ** cfg.decimals);
    }
}