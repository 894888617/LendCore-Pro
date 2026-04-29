// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {LiquidationLogic} from "../../src/logic/LiquidationLogic.sol";
import {PriceOracleAdapter} from "../../src/oracle/PriceOracleAdapter.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/**
 * @title LiquidationLogicTest
 * @notice LiquidationLogic 独立单元测试
 */
contract LiquidationLogicTest is Test {
    LiquidationLogic internal logic;
    PriceOracleAdapter internal oracle;

    MockERC20 internal weth;
    MockERC20 internal usdc;

    MockAggregatorV3 internal wethFeed;
    MockAggregatorV3 internal usdcFeed;

    address internal admin = address(0xA11CE);

    function setUp() public {
        vm.startPrank(admin);

        logic = new LiquidationLogic(5000);
        oracle = new PriceOracleAdapter(admin, 1 days);

        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        wethFeed = new MockAggregatorV3(8, 2000e8);
        usdcFeed = new MockAggregatorV3(8, 1e8);

        oracle.setPriceFeed(address(weth), address(wethFeed));
        oracle.setPriceFeed(address(usdc), address(usdcFeed));

        vm.stopPrank();
    }

    /**
     * @notice 测试健康因子低于 1 时可清算
     */
    function testIsLiquidatableByHealthFactorTrue() public view {
        bool result = logic.isLiquidatableByHealthFactor(0.8e18);
        assertTrue(result);
    }

    /**
     * @notice 测试健康因子等于 1 时不可清算
     */
    function testIsLiquidatableByHealthFactorFalseWhenEqualOne() public view {
        bool result = logic.isLiquidatableByHealthFactor(1e18);
        assertFalse(result);
    }

    /**
     * @notice 测试健康因子大于 1 时不可清算
     */
    function testIsLiquidatableByHealthFactorFalseWhenAboveOne() public view {
        bool result = logic.isLiquidatableByHealthFactor(1.2e18);
        assertFalse(result);
    }

    /**
     * @notice 测试最大可清算债务
     *
     * 条件：
     * - currentDebt = 2000 USDC
     * - closeFactor = 50%
     *
     * 预期：
     * - maxLiquidatable = 1000 USDC
     */
    function testCalculateMaxLiquidatableDebt() public view {
        uint256 maxDebt = logic.calculateMaxLiquidatableDebt(2000e6);
        assertEq(maxDebt, 1000e6);
    }

    /**
     * @notice 测试清算可扣押抵押品数量
     *
     * 条件：
     * - Bob 偿还 1000 USDC
     * - USDC = 1 USD
     * - WETH = 2000 USD
     * - liquidationBonus = 10500，即 105%
     *
     * 计算：
     * - repayValue = 1000 USD
     * - seizeValue = 1050 USD
     * - seizedCollateral = 1050 / 2000 = 0.525 WETH
     */
    function testCalculateSeizeAmountWithConfig() public view {
        uint256 seizedCollateral = logic.calculateSeizeAmountWithConfig(
            address(oracle),
            address(usdc),
            address(weth),
            1000e6,
            6,
            18,
            10500
        );

        assertEq(seizedCollateral, 0.525 ether);
    }

    /**
     * @notice 测试 WETH 价格变化后，扣押数量变化
     *
     * 条件：
     * - WETH 从 2000 USD 涨到 3000 USD
     * - Bob 仍然偿还 1000 USDC
     * - seizeValue = 1050 USD
     * - seizedCollateral = 1050 / 3000 = 0.35 WETH
     */
    function testCalculateSeizeAmountChangesWithPrice() public {
        wethFeed.setAnswer(3000e8);

        uint256 seizedCollateral = logic.calculateSeizeAmountWithConfig(
            address(oracle),
            address(usdc),
            address(weth),
            1000e6,
            6,
            18,
            10500
        );

        assertEq(seizedCollateral, 0.35 ether);
    }
}