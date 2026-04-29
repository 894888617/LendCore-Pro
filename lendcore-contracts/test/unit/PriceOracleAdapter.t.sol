// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {PriceOracleAdapter} from "../../src/oracle/PriceOracleAdapter.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {Errors} from "../../src/libraries/Errors.sol";

/**
 * @title PriceOracleAdapterTest
 * @notice PriceOracleAdapter 单元测试
 */
contract PriceOracleAdapterTest is Test {
    PriceOracleAdapter internal oracle;
    MockAggregatorV3 internal ethFeed;
    MockAggregatorV3 internal feed18Decimals;
    MockERC20 internal weth;

    address internal admin = address(0xA11CE);
    address internal user = address(0x1001);

    uint256 internal constant TEST_TIMESTAMP = 1_700_000_000;

    function setUp() public {
        vm.warp(TEST_TIMESTAMP);

        vm.startPrank(admin);

        oracle = new PriceOracleAdapter(admin, 1 days);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        ethFeed = new MockAggregatorV3(8, 3000e8);
        feed18Decimals = new MockAggregatorV3(18, 3000e18);

        oracle.setPriceFeed(address(weth), address(ethFeed));

        vm.stopPrank();
    }

    function testGetAssetPriceSuccess() public view {
        (uint256 price, uint256 updatedAt) = oracle.getAssetPrice(
            address(weth)
        );

        assertEq(price, 3000e8);
        assertGt(updatedAt, 0);
    }

    function testIsPriceValidSuccess() public view {
        bool valid = oracle.isPriceValid(address(weth));
        assertTrue(valid);
    }

    function testGetPriceDecimals() public view {
        assertEq(oracle.getPriceDecimals(), 8);
    }

    function testRevertWhenPriceFeedNotSet() public {
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);

        vm.expectPartialRevert(Errors.PriceFeedNotSet.selector);
        oracle.getAssetPrice(address(dai));
    }

    function testRevertWhenPriceIsZero() public {
        ethFeed.setAnswer(0);

        vm.expectPartialRevert(Errors.InvalidPrice.selector);
        oracle.getAssetPrice(address(weth));
    }

    function testRevertWhenPriceIsNegative() public {
        ethFeed.setAnswer(-1);

        vm.expectPartialRevert(Errors.InvalidPrice.selector);
        oracle.getAssetPrice(address(weth));
    }

    function testRevertWhenPriceIsStale() public {
        uint256 oldTimestamp = block.timestamp - 2 days;

        ethFeed.setAnswerWithTimestamp(3000e8, oldTimestamp);

        vm.expectPartialRevert(Errors.StalePrice.selector);
        oracle.getAssetPrice(address(weth));
    }

    function testIsPriceValidReturnsFalseWhenStale() public {
        uint256 oldTimestamp = block.timestamp - 2 days;

        ethFeed.setAnswerWithTimestamp(3000e8, oldTimestamp);

        bool valid = oracle.isPriceValid(address(weth));
        assertFalse(valid);
    }

    function testNormalize18DecimalsTo8Decimals() public {
        MockERC20 token = new MockERC20("TOKEN", "TOKEN", 18);

        vm.startPrank(admin);
        oracle.setPriceFeed(address(token), address(feed18Decimals));
        vm.stopPrank();

        (uint256 price, ) = oracle.getAssetPrice(address(token));

        assertEq(price, 3000e8);
    }

    function testOnlyAdminCanSetPriceFeed() public {
        MockERC20 token = new MockERC20("TOKEN", "TOKEN", 18);

        vm.startPrank(user);

        vm.expectRevert();
        oracle.setPriceFeed(address(token), address(ethFeed));

        vm.stopPrank();
    }

    function testSetMaxStalePeriod() public {
        vm.startPrank(admin);

        oracle.setMaxStalePeriod(2 days);

        assertEq(oracle.maxStalePeriod(), 2 days);

        vm.stopPrank();
    }
}