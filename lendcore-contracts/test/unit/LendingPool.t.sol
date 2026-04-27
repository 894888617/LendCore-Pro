// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {LendingPool} from "../../src/core/LendingPool.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockOracle} from "../../src/mocks/MockOracle.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";

/**
 * @title LendingPoolTest
 * @notice LendingPool 第一批单元测试
 */
contract LendingPoolTest is Test {
    LendingPool internal pool;
    MockERC20 internal weth;
    MockERC20 internal usdc;
    MockOracle internal oracle;

    address internal admin = address(0xA11CE);
    address internal treasury = address(0xBEEF);
    address internal alice = address(0x1001);
    address internal bob = address(0x2002);

    uint256 internal constant WETH_AMOUNT = 10 ether;
    uint256 internal constant USDC_LIQUIDITY = 100_000e6;

    function setUp() public {
        vm.startPrank(admin);

        pool = new LendingPool(admin, treasury);

        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        oracle = new MockOracle();

        oracle.setPrice(address(weth), 3000e8);
        oracle.setPrice(address(usdc), 1e8);

        DataTypes.MarketConfig memory wethConfig = DataTypes.MarketConfig({
            isListed: true,
            isCollateralEnabled: true,
            isBorrowEnabled: false,
            collateralFactorBps: 7500,
            liquidationThresholdBps: 8000,
            liquidationBonusBps: 10500,
            decimals: 18,
            oracle: address(oracle),
            interestRateModel: address(0x1234)
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
            interestRateModel: address(0x1234)
        });

        pool.initMarket(address(weth), wethConfig);
        pool.initMarket(address(usdc), usdcConfig);

        // 给 Alice 铸造 WETH 作为抵押品
        weth.mint(alice, WETH_AMOUNT);

        // 给 LendingPool 注入 USDC 流动性，供用户借出
        usdc.mint(address(pool), USDC_LIQUIDITY);

        // 给 Bob 铸造 USDC，作为清算人资金
        usdc.mint(bob, 10_000e6);

        vm.stopPrank();
    }

    function testInitMarketSuccess() public view {
        DataTypes.MarketConfig memory wethConfig = pool.getMarketConfig(
            address(weth)
        );

        assertTrue(wethConfig.isListed);
        assertTrue(wethConfig.isCollateralEnabled);
        assertFalse(wethConfig.isBorrowEnabled);
        assertEq(wethConfig.collateralFactorBps, 7500);
        assertEq(wethConfig.liquidationThresholdBps, 8000);
    }

    function testDepositSuccess() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        DataTypes.UserReservePosition memory position = pool.getUserPosition(
            alice,
            address(weth)
        );

        assertEq(position.supplied, 1 ether);
        assertTrue(position.useAsCollateral);

        DataTypes.MarketState memory state = pool.getMarketState(address(weth));
        assertEq(state.totalSupply, 1 ether);

        vm.stopPrank();
    }

    function testBorrowSuccess_CurrentlyNoHealthFactorCheck() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        pool.borrow(address(usdc), 1000e6);

        DataTypes.UserReservePosition memory debtPosition = pool.getUserPosition(
            alice,
            address(usdc)
        );

        assertEq(debtPosition.borrowed, 1000e6);
        assertEq(usdc.balanceOf(alice), 1000e6);

        vm.stopPrank();
    }

    function testRepaySuccess() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        pool.borrow(address(usdc), 1000e6);

        usdc.approve(address(pool), 400e6);
        uint256 actualRepaid = pool.repay(address(usdc), 400e6);

        assertEq(actualRepaid, 400e6);

        DataTypes.UserReservePosition memory debtPosition = pool.getUserPosition(
            alice,
            address(usdc)
        );

        assertEq(debtPosition.borrowed, 600e6);

        vm.stopPrank();
    }

    function testRepayMoreThanDebt() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        pool.borrow(address(usdc), 1000e6);

        usdc.approve(address(pool), 2000e6);
        uint256 actualRepaid = pool.repay(address(usdc), 2000e6);

        assertEq(actualRepaid, 1000e6);

        DataTypes.UserReservePosition memory debtPosition = pool.getUserPosition(
            alice,
            address(usdc)
        );

        assertEq(debtPosition.borrowed, 0);

        vm.stopPrank();
    }

    /**
     * @notice 测试用户存入 1 WETH 后，可借额度是否正确
     *
     * 条件：
     * - 1 WETH = 3000 USD
     * - 抵押因子 = 75%
     *
     * 预期：
     * - 可借额度 = 3000 * 75% = 2250 USD
     * - 因为系统使用 1e8 价格精度，所以结果是 2250e8
     */
    function testAvailableBorrowValueAfterDeposit() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        uint256 availableBorrowValue = pool.getAvailableBorrowValue(alice);

        assertEq(availableBorrowValue, 2250e8);

        vm.stopPrank();
    }

    /**
     * @notice 测试在可借额度内借款成功
     *
     * 条件：
     * - Alice 抵押 1 WETH
     * - 可借额度约 2250 USDC
     * - Alice 借 1000 USDC
     *
     * 预期：
     * - 借款成功
     * - Alice 的 USDC 债务为 1000e6
     */
    function testBorrowWithinCapacitySuccess() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        pool.borrow(address(usdc), 1000e6);

        DataTypes.UserReservePosition memory debtPosition = pool.getUserPosition(
            alice,
            address(usdc)
        );

        assertEq(debtPosition.borrowed, 1000e6);
        assertEq(usdc.balanceOf(alice), 1000e6);

        vm.stopPrank();
    }

    /**
     * @notice 测试借款超过可借额度时应失败
     *
     * 条件：
     * - Alice 抵押 1 WETH
     * - 可借额度 = 2250 USDC
     * - Alice 尝试借 3000 USDC
     *
     * 预期：
     * - revert InsufficientBorrowCapacity
     */
    function testBorrowExceedCapacityShouldRevert() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        vm.expectPartialRevert(Errors.InsufficientBorrowCapacity.selector);
        pool.borrow(address(usdc), 3000e6);

        vm.stopPrank();
    }

    /**
     * @notice 测试借款后的健康因子是否正确
     *
     * 条件：
     * - Alice 抵押 1 WETH
     * - WETH 价格 = 3000 USD
     * - 清算阈值 = 80%
     * - Alice 借 1000 USDC
     *
     * 计算：
     * - 清算调整后抵押价值 = 3000 * 80% = 2400 USD
     * - 债务价值 = 1000 USD
     * - 健康因子 = 2400 / 1000 = 2.4
     *
     * 预期：
     * - healthFactor = 2.4e18
     */
    function testHealthFactorAfterBorrow() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        pool.borrow(address(usdc), 1000e6);

        uint256 healthFactor = pool.getHealthFactor(alice);

        assertEq(healthFactor, 2.4e18);

        vm.stopPrank();
    }

    /**
     * @notice 测试没有债务时健康因子应为最大值
     *
     * 业务含义：
     * - 用户没有借款，就不存在清算风险
     * - 所以健康因子返回 type(uint256).max
     */
    function testHealthFactorWithoutDebtIsMax() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        uint256 healthFactor = pool.getHealthFactor(alice);

        assertEq(healthFactor, type(uint256).max);

        vm.stopPrank();
    }

    /**
     * @notice 测试提取过多抵押品时应失败
     *
     * 条件：
     * - Alice 抵押 1 WETH
     * - Alice 借 1000 USDC
     * - Alice 尝试提取 0.7 WETH
     *
     * 计算：
     * - 剩余抵押 = 0.3 WETH
     * - 剩余抵押价值 = 900 USD
     * - 清算调整后价值 = 900 * 80% = 720 USD
     * - 债务 = 1000 USD
     * - 健康因子 = 0.72 < 1
     *
     * 预期：
     * - revert HealthFactorTooLow
     */
    function testWithdrawTooMuchCollateralShouldRevert() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        pool.borrow(address(usdc), 1000e6);

        vm.expectPartialRevert(Errors.HealthFactorTooLow.selector);
        pool.withdraw(address(weth), 0.7 ether);

        vm.stopPrank();
    }

    /**
     * @notice 测试提取少量抵押品时成功
     *
     * 条件：
     * - Alice 抵押 1 WETH
     * - Alice 借 1000 USDC
     * - Alice 提取 0.1 WETH
     *
     * 计算：
     * - 剩余抵押 = 0.9 WETH
     * - 剩余抵押价值 = 2700 USD
     * - 清算调整后价值 = 2160 USD
     * - 债务 = 1000 USD
     * - 健康因子 = 2.16 > 1
     *
     * 预期：
     * - 提取成功
     */
    function testWithdrawSafeAmountSuccess() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        pool.borrow(address(usdc), 1000e6);

        pool.withdraw(address(weth), 0.1 ether);

        DataTypes.UserReservePosition memory position = pool.getUserPosition(
            alice,
            address(weth)
        );

        assertEq(position.supplied, 0.9 ether);

        vm.stopPrank();
    }

    /**
     * @notice 测试有债务时关闭唯一抵押品应失败
     *
     * 条件：
     * - Alice 抵押 1 WETH
     * - Alice 借 1000 USDC
     * - Alice 尝试关闭 WETH 抵押
     *
     * 预期：
     * - 因为关闭后没有任何抵押品，健康因子变为 0
     * - revert HealthFactorTooLow
     */
    function testDisableCollateralShouldRevertWhenDebtExists() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        pool.borrow(address(usdc), 1000e6);

        vm.expectPartialRevert(Errors.HealthFactorTooLow.selector);
        pool.setUseAsCollateral(address(weth), false);

        vm.stopPrank();
    }

    /**
     * @notice 测试没有债务时可以关闭抵押
     *
     * 条件：
     * - Alice 只存款，没有借款
     * - Alice 关闭 WETH 抵押
     *
     * 预期：
     * - 成功关闭
     */
    function testDisableCollateralWithoutDebtSuccess() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);

        pool.setUseAsCollateral(address(weth), false);

        DataTypes.UserReservePosition memory position = pool.getUserPosition(
            alice,
            address(weth)
        );

        assertFalse(position.useAsCollateral);

        vm.stopPrank();
    }

    /**
 * @notice 测试健康因子 >= 1 时不能清算
     *
     * 条件：
     * - Alice 抵押 1 WETH
     * - WETH = 3000 USD
     * - Alice 借 1000 USDC
     *
     * 健康因子：
     * - 3000 * 80% / 1000 = 2.4
     *
     * 预期：
     * - Bob 尝试清算失败
     */
    function testLiquidateShouldRevertWhenHealthFactorIsSafe() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);
        pool.borrow(address(usdc), 1000e6);

        vm.stopPrank();

        vm.startPrank(bob);

        usdc.approve(address(pool), 500e6);

        vm.expectPartialRevert(Errors.PositionNotLiquidatable.selector);
        pool.liquidate(alice, address(usdc), address(weth), 500e6);

        vm.stopPrank();
    }

    /**
 * @notice 测试 WETH 价格下跌后，健康因子下降到 1 以下
     *
     * 条件：
     * - Alice 抵押 1 WETH
     * - 初始 WETH = 3000 USD
     * - Alice 借 2000 USDC
     *
     * 初始健康因子：
     * - 3000 * 80% / 2000 = 1.2
     *
     * WETH 下跌到 2000 USD 后：
     * - 2000 * 80% / 2000 = 0.8
     *
     * 预期：
     * - 健康因子 = 0.8e18
     */
    function testHealthFactorDropsBelowOneAfterPriceFalls() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);
        pool.borrow(address(usdc), 2000e6);

        vm.stopPrank();

        oracle.setPrice(address(weth), 2000e8);

        uint256 healthFactor = pool.getHealthFactor(alice);

        assertEq(healthFactor, 0.8e18);
    }

    /**
 * @notice 测试价格下跌后清算成功
     *
     * 条件：
     * - Alice 抵押 1 WETH
     * - Alice 借 2000 USDC
     * - WETH 从 3000 USD 跌到 2000 USD
     * - Bob 清算 1000 USDC
     *
     * 清算计算：
     * - repayValue = 1000 USD
     * - liquidationBonus = 105%
     * - seizeValue = 1050 USD
     * - WETH price = 2000 USD
     * - seizedCollateral = 1050 / 2000 = 0.525 WETH
     *
     * 预期：
     * - Alice 债务从 2000 USDC 降到 1000 USDC
     * - Alice 抵押从 1 WETH 降到 0.475 WETH
     * - Bob 获得 0.525 WETH
     */
    function testLiquidateSuccessAfterPriceFalls() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);
        pool.borrow(address(usdc), 2000e6);

        vm.stopPrank();

        oracle.setPrice(address(weth), 2000e8);

        vm.startPrank(bob);

        usdc.approve(address(pool), 1000e6);
        pool.liquidate(alice, address(usdc), address(weth), 1000e6);

        vm.stopPrank();

        DataTypes.UserReservePosition memory debtPosition = pool
            .getUserPosition(alice, address(usdc));

        DataTypes.UserReservePosition memory collateralPosition = pool
            .getUserPosition(alice, address(weth));

        assertEq(debtPosition.borrowed, 1000e6);
        assertEq(collateralPosition.supplied, 0.475 ether);
        assertEq(weth.balanceOf(bob), 0.525 ether);
    }

    /**
 * @notice 测试单次清算最多只能清算 50% 债务
     *
     * 条件：
     * - Alice 借 2000 USDC
     * - 价格下跌后可清算
     * - Bob 尝试清算 2000 USDC
     *
     * 预期：
     * - 实际只清算 1000 USDC
     * - Alice 剩余债务 1000 USDC
     */
    function testLiquidateShouldRespectCloseFactor() public {
        vm.startPrank(alice);

        weth.approve(address(pool), 1 ether);
        pool.deposit(address(weth), 1 ether, true);
        pool.borrow(address(usdc), 2000e6);

        vm.stopPrank();

        oracle.setPrice(address(weth), 2000e8);

        vm.startPrank(bob);

        usdc.approve(address(pool), 2000e6);
        pool.liquidate(alice, address(usdc), address(weth), 2000e6);

        vm.stopPrank();

        DataTypes.UserReservePosition memory debtPosition = pool
            .getUserPosition(alice, address(usdc));

        assertEq(debtPosition.borrowed, 1000e6);
    }
}