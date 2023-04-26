pragma solidity ^0.7.6;

pragma experimental ABIEncoderV2;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import { IERC20 } from "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IAsset } from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import { IWETH } from "@balancer-labs/v2-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { ICronV1Pool } from "../src/interfaces/ICronV1Pool.sol";
import { ICronV1PoolEnums } from "../src/interfaces/pool/ICronV1PoolEnums.sol";
import { ICronV1PoolFactory } from "../src/interfaces/ICronV1PoolFactory.sol";

// forge test -vvvvv --fork-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY --match-path test/SimpleFlashSwapTest.t.sol

contract SimpleFlashSwap is Test {
  address public constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
  address public constant FACTORY = 0xD64c9CD98949C07F3C85730a37c13f4e78f35E77;

  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  // address with a lot of tokens
  address public constant WETH_RICHIE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
  address public constant USDC_RICHIE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;

  // USDC/WETH Pool:
  // URL: https://app.balancer.fi/#/ethereum/pool/0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019
  bytes32 public poolIdUSDCWETHLiquidPool = 0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019;

  IVault public vault = IVault(VAULT);

  // load user with 10k USDC, WETH
  function transferTokensLiquid(address _in) public {
    vm.startPrank(USDC_RICHIE);
    IERC20(USDC).transfer(_in, 1e15);
    vm.stopPrank();
    vm.startPrank(WETH_RICHIE);
    IERC20(WETH).transfer(_in, 1e22);
    vm.stopPrank();
    assertEq(IERC20(USDC).balanceOf(_in), 1e15);
    assertEq(IERC20(WETH).balanceOf(_in), 1e22);
  }

  function joinPool(
    address _in,
    address _token0,
    address _token1,
    uint256 _joinAmount0,
    uint256 _joinAmount1,
    uint256 _poolType
  ) public {
    // get pool from factory
    address pool = ICronV1PoolFactory(FACTORY).getPool(_token0, _token1, _poolType);
    // console.log("Pool address", pool);
    // setup information for pool join
    uint256 joinKind = uint256(ICronV1PoolEnums.JoinType.Join);
    bytes memory userData = getJoinUserData(joinKind, _joinAmount0, _joinAmount1);
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    // IAsset[] memory assets = _convertERC20sToAssets(tokens);
    uint256[] memory maxAmountsIn = new uint256[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      maxAmountsIn[i] = type(uint256).max;
    }
    // bool fromInternalBalance = false;
    // check LP tokens for _in is 0
    assertEq(ICronV1Pool(pool).balanceOf(_in), 0);
    // check token balances
    assertGt(IERC20(_token0).balanceOf(_in), _joinAmount0, "inufficient token0");
    assertGt(IERC20(_token1).balanceOf(_in), _joinAmount1, "insufficient token1");
    // start acting as _in
    vm.startPrank(_in);
    // approve tokens to be used by vault
    IERC20(tokens[0]).approve(VAULT, _joinAmount0);
    IERC20(tokens[1]).approve(VAULT, _joinAmount1);
    // call joinPool function on TWAMMs
    IVault(vault).joinPool(
      poolId,
      _in,
      payable (_in),
      IVault.JoinPoolRequest(
        _convertERC20sToAssets(tokens),
        maxAmountsIn,
        userData,
        false
      )
    );
    assertGt(ICronV1Pool(pool).balanceOf(_in), 0);
    vm.stopPrank();
  }

  // WETH overpriced, USDC underpriced in TWAMM pool
  // Sell WETH in TWAMM, buy WETH in Arb Pool
  // Note: need to calculate how much to swap, currently hardcoded for 10ETH
  function testForkFlashSwapWethUsdc01() public {
    address alice = vm.addr(100);
    transferTokensLiquid(alice);
    // 1 WETH = $3000
    // uint256 joinAmount0 = 3e12; // 3,000,000
    // uint256 joinAmount1 = 1e21; // 1000
    joinPool(alice, USDC, WETH, 3e12, 1e21, uint256(ICronV1PoolEnums.PoolType.Liquid));
    vm.label(alice, "alice");
    vm.label(USDC, "USDC");
    vm.label(WETH, "WETH");
    // get pool from factory
    address pool = ICronV1PoolFactory(FACTORY).getPool(USDC, WETH, uint256(ICronV1PoolEnums.PoolType.Liquid));
    // console.log("Pool address", pool);
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    // console.log("Pool ID", vm.toString(poolId));
    // uint256 swapAmount = 1e21;
    // setup information for short term swap through a TWAMM pool
    bytes memory userData = abi.encode(
      ICronV1PoolEnums.SwapType.RegularSwap, // swap type
      0
    );
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    (IERC20[] memory tokens2, , ) = vault.getPoolTokens(poolIdUSDCWETHLiquidPool);
    // IAsset[] memory assets = _convertERC20sToAssets(tokens);
    // IAsset[] memory assets2 = _convertERC20sToAssets(tokens2);
    int256[] memory limits = new int256[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      limits[i] = 0;
    }
    // ensure correct tokens are in the pool for batchswap step
    // console.log("USDC Index: ", getTokenIndex(USDC, poolId));
    // console.log("WETH Index: ", getTokenIndex(WETH, poolId));
    assertEq(address(tokens[getTokenIndex(USDC, poolId)]), USDC, "USDC Check 1");
    assertEq(address(tokens[getTokenIndex(WETH, poolId)]), WETH, "WETH Check 1");
    assertEq(tokens2.length, 2, "Tokens length");
    // console.log("USDC Index: ", getTokenIndex(USDC, poolIdUSDCWETHLiquidPool));
    // console.log("WETH Index: ", getTokenIndex(WETH, poolIdUSDCWETHLiquidPool));
    assertEq(address(tokens2[getTokenIndex(USDC, poolIdUSDCWETHLiquidPool)]), USDC, "USDC Check 2");
    assertEq(address(tokens2[getTokenIndex(WETH, poolIdUSDCWETHLiquidPool)]), WETH, "WETH Check 2");
    IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](2);
    // assetIn: WETH | assetOut: USDC
    swaps[0] = IVault.BatchSwapStep(
      poolId,
      getTokenIndex(WETH, poolId),
      getTokenIndex(USDC, poolId),
      1e19, // need to calculate this properly
      userData
    );
    // assetIn: USDC | assetOut: WETH
    swaps[1] = IVault.BatchSwapStep(
      poolIdUSDCWETHLiquidPool,
      getTokenIndex(USDC, poolIdUSDCWETHLiquidPool),
      getTokenIndex(WETH, poolIdUSDCWETHLiquidPool),
      0,
      ""
    );
    // start acting as alice
    vm.startPrank(alice);
    // swap amounts with vault
    int256[] memory deltas = vault.batchSwap(
      IVault.SwapKind.GIVEN_IN,
      swaps,
      _convertERC20sToAssets(tokens2),
      IVault.FundManagement(
        alice,
        false,
        payable (alice),
        false
      ),
      limits,
      block.timestamp + 1000
    );
    vm.stopPrank();
    console.log("Amount 0: ", vm.toString(deltas[0]));
    console.log("Amount 1: ", vm.toString(deltas[1]));
    // expect WETH returned from pool
    assertLt(deltas[1], 0);
  }


  // WETH underpriced, USDC overpriced in TWAMM pool
  // Sell WETH in Arb, buy WETH in TWAMM Pool
  // Note: need to calculate how much to swap, currently hardcoded for 10ETH
  function testForkFlashSwapWethUsdc10() public {
    address alice = vm.addr(100);
    transferTokensLiquid(alice);
    // 1 WETH = $1000
    // uint256 joinAmount0 = 1e12; // 1,000,000
    // uint256 joinAmount1 = 1e21; // 1000
    joinPool(alice, USDC, WETH, 1e12, 1e21, uint256(ICronV1PoolEnums.PoolType.Liquid));
    vm.label(alice, "alice");
    vm.label(USDC, "USDC");
    vm.label(WETH, "WETH");
    // get pool from factory
    address pool = ICronV1PoolFactory(FACTORY).getPool(USDC, WETH, uint256(ICronV1PoolEnums.PoolType.Liquid));
    // console.log("Pool address", pool);
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    // console.log("Pool ID", vm.toString(poolId));
    // uint256 swapAmount = 1e21;
    // setup information for short term swap through a TWAMM pool
    bytes memory userData = abi.encode(
      ICronV1PoolEnums.SwapType.RegularSwap, // swap type
      0
    );
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    (IERC20[] memory tokens2, , ) = vault.getPoolTokens(poolIdUSDCWETHLiquidPool);
    // IAsset[] memory assets = _convertERC20sToAssets(tokens);
    // IAsset[] memory assets2 = _convertERC20sToAssets(tokens2);
    int256[] memory limits = new int256[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      limits[i] = 0;
    }
    // ensure correct tokens are in the pool for batchswap step
    // console.log("USDC Index: ", getTokenIndex(USDC, poolId));
    // console.log("WETH Index: ", getTokenIndex(WETH, poolId));
    assertEq(address(tokens[getTokenIndex(USDC, poolId)]), USDC, "USDC Check 1");
    assertEq(address(tokens[getTokenIndex(WETH, poolId)]), WETH, "WETH Check 1");
    assertEq(tokens2.length, 2, "Tokens length");
    // console.log("USDC Index: ", getTokenIndex(USDC, poolIdUSDCWETHLiquidPool));
    // console.log("WETH Index: ", getTokenIndex(WETH, poolIdUSDCWETHLiquidPool));
    assertEq(address(tokens2[getTokenIndex(USDC, poolIdUSDCWETHLiquidPool)]), USDC, "USDC Check 2");
    assertEq(address(tokens2[getTokenIndex(WETH, poolIdUSDCWETHLiquidPool)]), WETH, "WETH Check 2");
    IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](2);
    // assetIn: WETH | assetOut: USDC
    swaps[0] = IVault.BatchSwapStep(
      poolIdUSDCWETHLiquidPool,
      getTokenIndex(WETH, poolIdUSDCWETHLiquidPool),
      getTokenIndex(USDC, poolIdUSDCWETHLiquidPool),
      1e19, // need to calculate this properly
      ""
    );
    // assetIn: USDC | assetOut: WETH
    swaps[1] = IVault.BatchSwapStep(
      poolId,
      getTokenIndex(USDC, poolId),
      getTokenIndex(WETH, poolId),
      0,
      userData
    );
    // start acting as alice
    vm.startPrank(alice);
    // swap amounts with vault
    int256[] memory deltas = vault.batchSwap(
      IVault.SwapKind.GIVEN_IN,
      swaps,
      _convertERC20sToAssets(tokens2),
      IVault.FundManagement(
        alice,
        false,
        payable (alice),
        false
      ),
      limits,
      block.timestamp + 1000
    );
    vm.stopPrank();
    console.log("Amount 0: ", vm.toString(deltas[0]));
    console.log("Amount 1: ", vm.toString(deltas[1]));
    assertEq(deltas[0], 0);
    // expect WETH returned from pool
    assertLt(deltas[1], 0);
  }

  function checkSwapBounds(IVault.BatchSwapStep[] memory swaps, IAsset[] memory assets) public view returns (bool inBound) {
    IVault.BatchSwapStep memory batchSwapStep;
    for (uint256 i = 0; i < swaps.length; ++i) {
      batchSwapStep = swaps[i];
      inBound = batchSwapStep.assetInIndex < assets.length &&
          batchSwapStep.assetOutIndex < assets.length;
      console.log("In bounds", inBound);
    }
  }

  function getTokenIndex(address _token, bytes32 _poolId) public view returns (uint256 index) {
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(_poolId);
    for (uint256 i = 0; i < tokens.length; i++) {
      if (address(tokens[i]) == _token) {
        index = i;
      }
    }
  }

  function getJoinUserData(
    uint256 _joinKind,
    uint256 _liquidity0,
    uint256 _liquidity1
  ) public pure returns (bytes memory userData) {
    userData = getJoinUserDataWithMin(_joinKind, _liquidity0, _liquidity1, 0, 0);
  }
  
  function getJoinUserDataWithMin(
    uint256 _joinKind,
    uint256 _liquidity0,
    uint256 _liquidity1,
    uint256 _minLiquidity0,
    uint256 _minLiquidity1
  ) public pure returns (bytes memory userData) {
    uint256[] memory balances = new uint256[](2);
    balances[0] = _liquidity0;
    balances[1] = _liquidity1;
    uint256[] memory minTokenAmt = new uint256[](2);
    minTokenAmt[0] = _minLiquidity0;
    minTokenAmt[1] = _minLiquidity1;
    userData = abi.encode(_joinKind, balances, minTokenAmt);
  }

  function _convertERC20sToAssets(IERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      assets := tokens
    }
  }

}
