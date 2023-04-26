// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import "../src/UniswapV3Flash.sol";

// forge test -vv --gas-report --fork-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY --match-path test/UniswapV3FlashTest.t.sol

contract UniswapV3FlashTest is Test {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint24 public constant POOL_FEE = 500;

    IWETH private weth = IWETH(WETH);
    IERC20 private usdc = IERC20(USDC);

    UniswapV3Flash private uni = new UniswapV3Flash(USDC, WETH, POOL_FEE);

    function setUp() public {}

    function testFlash() public {
        // Approve WETH fee
        weth.deposit{value: 1e18}();
        weth.approve(address(uni), 1e18);

        uint256 balBefore = weth.balanceOf(address(this));
        uni.flash(0, 100 * 1e18);
        uint256 balAfter = weth.balanceOf(address(this));

        uint256 fee = balBefore - balAfter;
        console.log("WETH fee", fee);
        console.log("Bal Before", balBefore);
        console.log("Bal After", balAfter);
    }
}
