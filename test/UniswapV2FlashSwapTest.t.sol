// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import "../src/UniswapV2FlashSwap.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

// forge test -vv --gas-report --fork-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY --match-path test/UniswapV2FlashSwap.t.sol

contract UniswapV2FlashSwapTest is Test {
    IWETH private weth = IWETH(WETH);

    UniswapV2FlashSwap private uni = new UniswapV2FlashSwap();

    function setUp() public {}

    function testFlashSwap() public {
        weth.deposit{value: 1e18}();
        // Approve flash swap fee
        weth.approve(address(uni), 1e18);

        uint amountToBorrow = 10 * 1e18;
        uni.flashSwap(amountToBorrow);

        assertGt(uni.amountToRepay(), amountToBorrow);
    }
}
