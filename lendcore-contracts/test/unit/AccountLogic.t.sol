// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {LendingPool} from "../../src/core/LendingPool.sol";
import {AccountLogic} from "../../src/logic/AccountLogic.sol";
import {PriceOracleAdapter} from "../../src/oracle/PriceOracleAdapter.sol";
import {InterestRateModel} from "../../src/interest/InterestRateModel.sol";
import {PoolConfigurator} from "../../src/core/PoolConfigurator.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/**
 * @title AccountLogicTest
 * @notice AccountLogic 独立测试
 */
contract AccountLogicTest is Test {
    LendingPool internal pool;
    AccountLogic internal accountLogic;
    PoolConfigurator internal configurator;

    MockERC20 internal weth;
    MockERC20 internal usdc;

    PriceOracleAdapter internal oracle;
    InterestRateModel internal rateModel;

    MockAggregatorV3 internal wethFeed;
    MockAggregatorV3 internal usdcFeed;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0xBEEF);
    address internal alice = address(0x1001);

    function setUp() public {
        vm.startPrank(admin);

        pool = new LendingPool(admin, treasury);
        accountLogic = AccountLogic(pool.getAccountLogic());
        configurator = PoolConfigurator(pool.getPoolConfigurator());

        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        oracle = new PriceOracleAdapter(admin, 1 days);

        wethFeed = new MockAggregatorV3(8, 3000e8);
        usdcFeed = new MockAggregatorV3(8, 1e8);

        oracle.setPriceFeed(address(weth), address(wethFeed));
        oracle.setPriceFeed(address(usdc), address(usdcFeed));

        rateModel = new InterestRateModel(0.02e18, 0.20e18, 0.10e18);

        DataTypes.MarketConfig memory wethConfig = DataTypes.MarketConfig({
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

        DataTypes.MarketConfig memory usdcConfig = DataTypes.MarketConfig({
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

        configurator.initMarket(address(weth), wethConfig);
        configurator.initMarket(address(usdc), usdcConfig);

        weth.mint(alice, 10 ether);
        usdc.mint(address(pool), 100_000e6);

        vm.stopPrank();
    }

    function testGetUserTotalCollateralValue() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        vm.stopPrank();

        uint256 collateralValue = accountLogic.getUserTotalCollateralValue(
            alice
        );

        assertEq(collateralValue, 3000e8);
    }

    function testGetUserBorrowCapacity() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        vm.stopPrank();

        uint256 capacity = accountLogic.getUserBorrowCapacity(alice);

        assertEq(capacity, 2250e8);
    }

    function testGetHealthFactorAfterBorrow() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);
        pool.borrow(address(usdc), 1000e6);

        vm.stopPrank();

        uint256 healthFactor = accountLogic.getHealthFactor(alice);

        assertEq(healthFactor, 2.4e18);
    }

    function testHealthFactorDropsAfterPriceFalls() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);
        pool.borrow(address(usdc), 2000e6);

        vm.stopPrank();

        wethFeed.setAnswer(2000e8);

        uint256 healthFactor = accountLogic.getHealthFactor(alice);

        assertEq(healthFactor, 0.8e18);
    }

    function testHealthFactorAfterWithdraw() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);
        pool.borrow(address(usdc), 1000e6);

        vm.stopPrank();

        uint256 hfAfter = accountLogic.getHealthFactorAfterWithdraw(
            alice,
            address(weth),
            0.1 ether
        );

        assertEq(hfAfter, 2.16e18);
    }

    function testHealthFactorAfterDisableCollateral() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);
        pool.borrow(address(usdc), 1000e6);

        vm.stopPrank();

        uint256 hfAfter = accountLogic.getHealthFactorAfterDisableCollateral(
            alice,
            address(weth)
        );

        assertEq(hfAfter, 0);
    }
}