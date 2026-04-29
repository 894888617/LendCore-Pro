// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {LendingPool} from "../../src/core/LendingPool.sol";
import {PoolConfigurator} from "../../src/core/PoolConfigurator.sol";
import {PriceOracleAdapter} from "../../src/oracle/PriceOracleAdapter.sol";
import {InterestRateModel} from "../../src/interest/InterestRateModel.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";

/**
 * @title PoolConfiguratorTest
 * @notice PoolConfigurator 模块单元测试
 */
contract PoolConfiguratorTest is Test {
    LendingPool internal pool;
    PoolConfigurator internal configurator;

    MockERC20 internal weth;
    MockERC20 internal usdc;

    PriceOracleAdapter internal oracle;
    InterestRateModel internal rateModel;

    MockAggregatorV3 internal wethFeed;
    MockAggregatorV3 internal usdcFeed;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0xBEEF);
    address internal user = address(0x1001);

    function setUp() public {
        vm.startPrank(admin);

        pool = new LendingPool(admin, treasury);
        configurator = PoolConfigurator(pool.getPoolConfigurator());

        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        oracle = new PriceOracleAdapter(admin, 1 days);

        wethFeed = new MockAggregatorV3(8, 3000e8);
        usdcFeed = new MockAggregatorV3(8, 1e8);

        oracle.setPriceFeed(address(weth), address(wethFeed));
        oracle.setPriceFeed(address(usdc), address(usdcFeed));

        rateModel = new InterestRateModel(0.02e18, 0.20e18, 0.10e18);

        vm.stopPrank();
    }

    function _wethConfig() internal view returns (DataTypes.MarketConfig memory) {
        return
                            DataTypes.MarketConfig({
                isListed: true,
                isCollateralEnabled: true,
                isBorrowEnabled: false,
                collateralFactorBps: 7500,
                liquidationThresholdBps: 8000,
                liquidationBonusBps: 10500,
                decimals: 18,
                oracle: address(oracle),
                interestRateModel: address(rateModel)
            });
    }

    function _usdcConfig() internal view returns (DataTypes.MarketConfig memory) {
        return
                            DataTypes.MarketConfig({
                isListed: true,
                isCollateralEnabled: false,
                isBorrowEnabled: true,
                collateralFactorBps: 0,
                liquidationThresholdBps: 0,
                liquidationBonusBps: 10500,
                decimals: 6,
                oracle: address(oracle),
                interestRateModel: address(rateModel)
            });
    }

    /**
     * @notice 测试通过 PoolConfigurator 初始化市场
     */
    function testInitMarketThroughConfigurator() public {
        vm.startPrank(admin);

        configurator.initMarket(address(weth), _wethConfig());

        vm.stopPrank();

        DataTypes.MarketConfig memory cfg = pool.getMarketConfig(address(weth));

        assertTrue(cfg.isListed);
        assertTrue(cfg.isCollateralEnabled);
        assertFalse(cfg.isBorrowEnabled);
        assertEq(cfg.collateralFactorBps, 7500);
        assertEq(cfg.liquidationThresholdBps, 8000);
    }

    /**
     * @notice 测试通过 PoolConfigurator 修改抵押因子
     */
    function testSetCollateralFactorThroughConfigurator() public {
        vm.startPrank(admin);

        configurator.initMarket(address(weth), _wethConfig());
        configurator.setCollateralFactor(address(weth), 7000);

        vm.stopPrank();

        DataTypes.MarketConfig memory cfg = pool.getMarketConfig(address(weth));

        assertEq(cfg.collateralFactorBps, 7000);
    }

    /**
     * @notice 测试通过 PoolConfigurator 修改借款开关
     */
    function testSetBorrowEnabledThroughConfigurator() public {
        vm.startPrank(admin);

        configurator.initMarket(address(usdc), _usdcConfig());
        configurator.setBorrowEnabled(address(usdc), false);

        vm.stopPrank();

        DataTypes.MarketConfig memory cfg = pool.getMarketConfig(address(usdc));

        assertFalse(cfg.isBorrowEnabled);
    }

    /**
     * @notice 测试通过 PoolConfigurator 暂停和恢复协议
     */
    function testPauseAndUnpauseThroughConfigurator() public {
        vm.startPrank(admin);

        configurator.pauseProtocol();
        assertTrue(pool.isPaused());

        configurator.unpauseProtocol();
        assertFalse(pool.isPaused());

        vm.stopPrank();
    }

    /**
     * @notice 测试普通用户不能通过 PoolConfigurator 初始化市场
     */
    function testNonAdminCannotInitMarketThroughConfigurator() public {
        vm.startPrank(user);

        vm.expectRevert();
        configurator.initMarket(address(weth), _wethConfig());

        vm.stopPrank();
    }

    /**
     * @notice 测试 PoolConfigurator 地址是否正确记录在 LendingPool 中
     */
    function testGetPoolConfigurator() public view {
        assertEq(pool.getPoolConfigurator(), address(configurator));
    }

    /**
     * @notice 测试管理员不能绕过 PoolConfigurator 直接初始化市场
     */
    function testAdminCannotInitMarketDirectlyOnPool() public {
        vm.startPrank(admin);

        vm.expectPartialRevert(Errors.NotPoolConfigurator.selector);
        pool.initMarket(address(weth), _wethConfig());

        vm.stopPrank();
    }

    /**
     * @notice 测试管理员不能绕过 PoolConfigurator 直接暂停协议
     */
    function testAdminCannotPausePoolDirectly() public {
        vm.startPrank(admin);

        vm.expectPartialRevert(Errors.NotPoolConfigurator.selector);
        pool.pauseProtocol();

        vm.stopPrank();
    }
}