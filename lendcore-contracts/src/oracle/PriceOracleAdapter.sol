// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IPriceOracleAdapter} from "../interfaces/IPriceOracleAdapter.sol";
import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title PriceOracleAdapter
 * @notice LendCore Pro 价格预言机适配器
 * @dev
 * 作用：
 * 1. 管理 asset => price feed 的映射
 * 2. 从 Chainlink 风格 price feed 读取价格
 * 3. 统一转换为 1e8 精度
 * 4. 检查价格是否为 0
 * 5. 检查价格是否过期
 *
 * 当前 V1 约定：
 * - 输出价格统一为 1e8 精度
 * - maxStalePeriod 控制价格最大允许过期时间
 */
contract PriceOracleAdapter is IPriceOracleAdapter, AccessControl {
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");

    uint8 public constant PRICE_DECIMALS = 8;

    mapping(address => address) private s_priceFeeds;

    uint256 public maxStalePeriod;

    event PriceFeedUpdated(
        address indexed asset,
        address oldFeed,
        address newFeed
    );

    event MaxStalePeriodUpdated(uint256 oldValue, uint256 newValue);

    constructor(address admin, uint256 maxStalePeriod_) {
        if (admin == address(0)) {
            revert Errors.ZeroAddress();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ADMIN_ROLE, admin);

        maxStalePeriod = maxStalePeriod_;
    }

    /**
     * @notice 设置某资产的价格源
     * @param asset 资产地址
     * @param feed Chainlink 风格 Aggregator 地址
     */
    function setPriceFeed(
        address asset,
        address feed
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        if (asset == address(0) || feed == address(0)) {
            revert Errors.ZeroAddress();
        }

        address oldFeed = s_priceFeeds[asset];
        s_priceFeeds[asset] = feed;

        emit PriceFeedUpdated(asset, oldFeed, feed);
    }

    /**
     * @notice 设置最大价格过期时间
     * @param newMaxStalePeriod 新过期时间，单位秒
     */
    function setMaxStalePeriod(
        uint256 newMaxStalePeriod
    ) external onlyRole(ORACLE_ADMIN_ROLE) {
        uint256 oldValue = maxStalePeriod;
        maxStalePeriod = newMaxStalePeriod;

        emit MaxStalePeriodUpdated(oldValue, newMaxStalePeriod);
    }

    /**
     * @notice 查询某资产的价格源
     */
    function getPriceFeed(address asset) external view returns (address) {
        return s_priceFeeds[asset];
    }

    /**
     * @inheritdoc IPriceOracleAdapter
     */
    function getAssetPrice(
        address asset
    ) external view returns (uint256 price, uint256 updatedAt) {
        address feed = s_priceFeeds[asset];

        if (feed == address(0)) {
            revert Errors.PriceFeedNotSet(asset);
        }

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 feedUpdatedAt,
            uint80 answeredInRound
        ) = IAggregatorV3(feed).latestRoundData();

        if (roundId == 0 || answeredInRound < roundId) {
            revert Errors.InvalidPriceRound(asset);
        }

        if (answer <= 0) {
            revert Errors.InvalidPrice(asset);
        }

        if (feedUpdatedAt == 0) {
            revert Errors.InvalidPrice(asset);
        }

        if (maxStalePeriod > 0) {
            uint256 currentTimestamp = block.timestamp;

            if (currentTimestamp - feedUpdatedAt > maxStalePeriod) {
                revert Errors.StalePrice(asset, feedUpdatedAt);
            }
        }

        uint8 feedDecimals = IAggregatorV3(feed).decimals();

        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 positiveAnswer = uint256(answer); // safe: answer <= 0 was rejected above

        price = _normalizeTo1e8(positiveAnswer, feedDecimals);
        updatedAt = feedUpdatedAt;
    }

    /**
     * @inheritdoc IPriceOracleAdapter
     */
    function isPriceValid(address asset) external view returns (bool) {
        try this.getAssetPrice(asset) returns (
            uint256 price,
            uint256 updatedAt
        ) {
            return price > 0 && updatedAt > 0;
        } catch {
            return false;
        }
    }

    /**
     * @inheritdoc IPriceOracleAdapter
     */
    function getPriceDecimals() external pure returns (uint8) {
        return PRICE_DECIMALS;
    }

    /**
     * @notice 把 feed 价格统一转换成 1e8 精度
     */
    function _normalizeTo1e8(
        uint256 price,
        uint8 feedDecimals
    ) internal pure returns (uint256) {
        if (feedDecimals == PRICE_DECIMALS) {
            return price;
        }

        if (feedDecimals > PRICE_DECIMALS) {
            return price / (10 ** (feedDecimals - PRICE_DECIMALS));
        }

        return price * (10 ** (PRICE_DECIMALS - feedDecimals));
    }
}