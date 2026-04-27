// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockOracle
 * @notice 测试用价格预言机
 * @dev
 * 当前 LendingPool 第一版还没有真正读取 Oracle。
 * 这个 MockOracle 是为了下一步 AccountLogic / 健康因子计算提前准备。
 *
 * 价格统一使用 1e8 精度。
 * 例如：
 * - ETH = 3000 * 1e8
 * - USDC = 1 * 1e8
 */
contract MockOracle {
    uint8 public constant PRICE_DECIMALS = 8;

    mapping(address => uint256) private s_prices;
    mapping(address => uint256) private s_updatedAt;

    /**
     * @notice 设置资产价格
     * @param asset 资产地址
     * @param price 价格，1e8 精度
     */
    function setPrice(address asset, uint256 price) external {
        s_prices[asset] = price;
        s_updatedAt[asset] = block.timestamp;
    }

    /**
     * @notice 获取资产价格
     * @param asset 资产地址
     * @return price 价格
     * @return updatedAt 更新时间
     */
    function getAssetPrice(
        address asset
    ) external view returns (uint256 price, uint256 updatedAt) {
        return (s_prices[asset], s_updatedAt[asset]);
    }

    /**
     * @notice 判断价格是否有效
     */
    function isPriceValid(address asset) external view returns (bool) {
        return s_prices[asset] > 0 && s_updatedAt[asset] > 0;
    }

    /**
     * @notice 返回价格精度
     */
    function getPriceDecimals() external pure returns (uint8) {
        return PRICE_DECIMALS;
    }
}