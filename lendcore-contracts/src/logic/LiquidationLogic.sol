// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILiquidationLogic} from "../interfaces/ILiquidationLogic.sol";
import {IPriceOracleAdapter} from "../interfaces/IPriceOracleAdapter.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title LiquidationLogic
 * @notice LendCore Pro 清算计算模块
 * @dev
 * 这个合约/模块只负责清算相关的纯计算，不负责：
 * - 用户资产转账
 * - 修改用户仓位
 * - 修改市场总债务
 *
 * LendingPool 负责执行清算流程：
 * 1. 校验用户可清算
 * 2. 计算 actualRepay
 * 3. 计算 seizedCollateral
 * 4. 转入 debtAsset
 * 5. 扣减债务和抵押
 * 6. 转出 collateralAsset
 *
 * LiquidationLogic 负责计算：
 * - 最大可清算债务
 * - 可扣押抵押品数量
 */
contract LiquidationLogic is ILiquidationLogic {
    uint256 public constant BPS = 10_000;
    uint256 public constant WAD = 1e18;

    /**
     * @notice 单次最大清算比例
     * @dev 5000 = 50%
     */
    uint16 public immutable closeFactorBps;

    constructor(uint16 closeFactorBps_) {
        if (closeFactorBps_ == 0 || closeFactorBps_ > BPS) {
            revert Errors.InvalidLiquidationThreshold(closeFactorBps_);
        }

        closeFactorBps = closeFactorBps_;
    }

    /**
     * @inheritdoc ILiquidationLogic
     * @dev
     * 这个接口版本缺少 healthFactor 入参。
     * 当前为了兼容旧接口，先保留但不建议在 V1 使用。
     * LendingPool 里会直接用 healthFactor 判断。
     */
    function isLiquidatable(address) external pure returns (bool) {
        revert("USE_IS_LIQUIDATABLE_BY_HF");
    }

    /**
     * @inheritdoc ILiquidationLogic
     * @dev
     * 这个接口版本缺少 currentDebt 入参。
     * 当前为了兼容旧接口，先保留但不建议在 V1 使用。
     * V1 请使用 calculateMaxLiquidatableDebt(currentDebt)。
     */
    function getMaxLiquidatableDebt(
        address,
        address
    ) external pure returns (uint256) {
        revert("USE_CALCULATE_MAX_LIQUIDATABLE_DEBT");
    }

    /**
     * @inheritdoc ILiquidationLogic
     * @dev
     * 这个接口版本缺少 oracle/config 入参。
     * 当前为了兼容旧接口，先保留但不建议在 V1 使用。
     * V1 请使用 calculateSeizeAmount(...)。
     */
    function calculateSeizeAmount(
        address,
        address,
        uint256
    ) external pure returns (uint256) {
        revert("USE_EXTENDED_CALCULATE_SEIZE_AMOUNT");
    }

    /**
     * @notice 根据健康因子判断是否可清算
     * @param healthFactor 健康因子，WAD 精度，1e18 表示 1
     * @return true 表示可清算
     */
    function isLiquidatableByHealthFactor(
        uint256 healthFactor
    ) external pure returns (bool) {
        return healthFactor < WAD;
    }

    /**
     * @notice 计算最大可清算债务
     * @param currentDebt 当前债务数量
     * @return maxDebt 最大可清算数量
     */
    function calculateMaxLiquidatableDebt(
        uint256 currentDebt
    ) public view returns (uint256 maxDebt) {
        return (currentDebt * closeFactorBps) / BPS;
    }

    /**
     * @notice 计算清算人可获得的抵押品数量
     * @param oracle 价格预言机适配器地址
     * @param debtAsset 债务资产地址
     * @param collateralAsset 抵押资产地址
     * @param repayAmount 偿还债务数量
     * @param debtDecimals 债务资产精度
     * @param collateralDecimals 抵押资产精度
     * @param liquidationBonusBps 清算奖励，例如 10500 = 105%
     * @return seizedCollateral 可扣押抵押品数量
     *
     * 计算逻辑：
     * 1. repayValue = repayAmount * debtPrice / 10 ** debtDecimals
     * 2. seizeValue = repayValue * liquidationBonusBps / BPS
     * 3. seizedCollateral = seizeValue * 10 ** collateralDecimals / collateralPrice
     */
    function calculateSeizeAmountWithConfig(
        address oracle,
        address debtAsset,
        address collateralAsset,
        uint256 repayAmount,
        uint8 debtDecimals,
        uint8 collateralDecimals,
        uint16 liquidationBonusBps
    ) external view returns (uint256 seizedCollateral) {
        if (oracle == address(0)) {
            revert Errors.ZeroAddress();
        }

        if (repayAmount == 0) {
            revert Errors.ZeroAmount();
        }

        (uint256 debtPrice, ) = IPriceOracleAdapter(oracle).getAssetPrice(
            debtAsset
        );

        (uint256 collateralPrice, ) = IPriceOracleAdapter(oracle).getAssetPrice(
            collateralAsset
        );

        if (debtPrice == 0) {
            revert Errors.InvalidPrice(debtAsset);
        }

        if (collateralPrice == 0) {
            revert Errors.InvalidPrice(collateralAsset);
        }

        uint256 repayValue = (repayAmount * debtPrice) /
            (10 ** debtDecimals);

        uint256 seizeValue = (repayValue * liquidationBonusBps) / BPS;

        seizedCollateral =
            (seizeValue * (10 ** collateralDecimals)) /
            collateralPrice;
    }
}