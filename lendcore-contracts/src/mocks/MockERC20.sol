// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice 测试用 ERC20 Token
 * @dev
 * 用来模拟：
 * - WETH 抵押资产
 * - MockUSDC 借贷资产
 *
 * 这个合约只用于本地测试和测试网演示，不用于生产。
 */
contract MockERC20 is ERC20 {
    uint8 private immutable i_decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        i_decimals = decimals_;
    }

    /**
     * @notice 返回 token 精度
     */
    function decimals() public view override returns (uint8) {
        return i_decimals;
    }

    /**
     * @notice 测试铸币函数
     * @dev 任何人都能 mint，只用于测试环境
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}