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

// forge test -vvvvv --fork-url https://eth-goerli.g.alchemy.com/v2/$ALCHEMY_API_KEY --match-path test/TraderActionsForkTest.t.sol

contract TraderActionsForkTest is Test {
  address public constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
  address public constant WETH = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
  address public constant USDC = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
  address public constant FACTORY = 0x3Db2b6cB59Bb9717cfBaBb805a888e59e3292AAE;

  IVault public vault = IVault(VAULT);

  function testForkJoinPool() public {
    address alice = address(1);
    // give alice 1 WETH, 1000 USDC
    deal(USDC, alice, 1000 ether);
    deal(WETH, alice, 1 ether);
    // get pool from factory
    address pool = ICronV1PoolFactory(FACTORY).getPool(USDC, WETH, uint256(ICronV1PoolEnums.PoolType.Liquid));
    // setup information for pool join
    uint256 joinKind = uint256(ICronV1PoolEnums.JoinType.Join);
    bytes memory userData = getJoinUserData(joinKind, IERC20(USDC).balanceOf(alice), IERC20(WETH).balanceOf(alice));
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    IAsset[] memory assets = _convertERC20sToAssets(tokens);
    uint256[] memory maxAmountsIn = new uint256[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      maxAmountsIn[i] = type(uint256).max;
    }
    bool fromInternalBalance = false;
    // check LP tokens for alice is 0
    assertEq(ICronV1Pool(pool).balanceOf(alice), 0);
    // start acting as Alice
    vm.startPrank(alice);
    // approve tokens to be used by vault
    IERC20(tokens[0]).approve(VAULT, IERC20(USDC).balanceOf(alice));
    IERC20(tokens[1]).approve(VAULT, IERC20(WETH).balanceOf(alice));
    // call joinPool function on TWAMMs
    IVault(vault).joinPool(
      poolId,
      alice,
      payable (alice),
      IVault.JoinPoolRequest(
        assets,
        maxAmountsIn,
        userData,
        fromInternalBalance
      )
    );
    assertGt(ICronV1Pool(pool).balanceOf(alice), 0);
    vm.stopPrank();
  }

  function testForkLongTermSwap() public {
    testForkJoinPool();
    address alice = address(1);
    address pool = ICronV1PoolFactory(FACTORY).getPool(USDC, WETH, uint256(ICronV1PoolEnums.PoolType.Liquid));
    deal(USDC, alice, 1000 ether);
    deal(WETH, alice, 1 ether);
    uint256 swapAmount = 100e6;
    uint256 intervals = 10;
    // setup information for long term swap
    bytes memory userData = abi.encode(
      ICronV1PoolEnums.SwapType.LongTermSwap, // swap type
      intervals
    );
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    IAsset[] memory assets = _convertERC20sToAssets(tokens);
    // start acting as alice
    vm.startPrank(alice);
    // approve tokens to spend from this contract in the vault
    tokens[0].approve(VAULT, swapAmount);
    // swap amounts with vault
    vault.swap(
      IVault.SingleSwap(
        poolId,
        IVault.SwapKind.GIVEN_IN,
        assets[0],
        assets[1],
        swapAmount,
        userData
      ),
      IVault.FundManagement(
        alice,
        false,
        payable (alice),
        false
      ),
      0,
      block.timestamp + 1000
    );
    vm.stopPrank();
  }

  function testForkShortTermSwap() public {
    testForkJoinPool();
    address alice = address(1);
    address pool = ICronV1PoolFactory(FACTORY).getPool(USDC, WETH, uint256(ICronV1PoolEnums.PoolType.Liquid));
    deal(USDC, alice, 1000 ether);
    deal(WETH, alice, 1 ether);
    uint256 swapAmount = 10e6;
    // setup information for long term swap
    bytes memory userData = abi.encode(
      ICronV1PoolEnums.SwapType.RegularSwap, // swap type
      0
    );
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    IAsset[] memory assets = _convertERC20sToAssets(tokens);
    // start acting as alice
    vm.startPrank(alice);
    // approve tokens to spend from this contract in the vault
    tokens[0].approve(VAULT, swapAmount);
    // swap amounts with vault
    vault.swap(
      IVault.SingleSwap(
        poolId,
        IVault.SwapKind.GIVEN_IN,
        assets[0],
        assets[1],
        swapAmount,
        userData
      ),
      IVault.FundManagement(
        alice,
        false,
        payable (alice),
        false
      ),
      0,
      block.timestamp + 1000
    );
    vm.stopPrank();
  }

  function testForkCancelOrder() public {
    testForkLongTermSwap();
    address alice = address(1);
    address pool = ICronV1PoolFactory(FACTORY).getPool(USDC, WETH, uint256(ICronV1PoolEnums.PoolType.Liquid));
    uint256 orderId = 0;
    // build userData field
    bytes memory userData = abi.encode(
      ICronV1PoolEnums.ExitType.Cancel,
      orderId
    );
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    IAsset[] memory assets = _convertERC20sToAssets(tokens);
    uint256[] memory minAmountOut = getMinAmountsOut(0, 0);
    // start acting as Alice
    vm.startPrank(alice);
    // as this is a fork, blocks haven't progressed so nothing to cancel
    vm.expectRevert("CFI#011");
    IVault(vault).exitPool(
      poolId,
      alice,
      payable (alice),
      IVault.ExitPoolRequest(
        assets,
        minAmountOut,
        userData,
        false
      )
    );
    vm.stopPrank();
  }

  function testForkWithdrawOrder() public {
    testForkLongTermSwap();
    address alice = address(1);
    address pool = ICronV1PoolFactory(FACTORY).getPool(USDC, WETH, uint256(ICronV1PoolEnums.PoolType.Liquid));
    uint256 orderId = 0;
    // build userData field
    bytes memory userData = abi.encode(
      ICronV1PoolEnums.ExitType.Withdraw,
      orderId
    );
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    IAsset[] memory assets = _convertERC20sToAssets(tokens);
    uint256[] memory minAmountOut = getMinAmountsOut(0, 0);
    // start acting as Alice
    vm.startPrank(alice);
    // as this is a fork, blocks haven't progressed so nothing to wihdraw
    vm.expectRevert("CFI#011");
    IVault(vault).exitPool(
      poolId,
      alice,
      payable (alice),
      IVault.ExitPoolRequest(
        assets,
        minAmountOut,
        userData,
        false
      )
    );
    vm.stopPrank();
  }
  
  function getMinAmountsOut(uint256 minToken0, uint256 minToken1)
           public pure
           returns(uint256[] memory minAmountsOut)
  {
    minAmountsOut = new uint256[](2);
    minAmountsOut[0] = minToken0;
    minAmountsOut[1] = minToken1;
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
