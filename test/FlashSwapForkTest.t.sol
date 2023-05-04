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

// forge test -vvvvv --fork-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY --match-path test/FlashSwapForkTest.t.sol

contract FlashSwapForkTest is Test {
  address public constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
  address public constant FACTORY = 0xD64c9CD98949C07F3C85730a37c13f4e78f35E77;
  address public constant ADMIN = 0xe122Eff60083bC550ACbf31E7d8197A58d436b39;

  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
  address public constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
  address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

  // address with a lot of tokens
  address public constant WETH_RICHIE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
  address public constant USDC_RICHIE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
  address public constant RETH_RICHIE = 0x7C5aaA2a20b01df027aD032f7A768aC015E77b86;
  address public constant WSTETH_RICHIE = 0x248cCBf4864221fC0E840F29BB042ad5bFC89B5c;

  // Composable Pool: wstETH, sfrxETH, rETH (0.04%)
  // URL: https://app.balancer.fi/#/ethereum/pool/0x5aee1e99fe86960377de9f88689616916d5dcabe000000000000000000000467
  bytes32 public poolIdComposablePool = 0x5aee1e99fe86960377de9f88689616916d5dcabe000000000000000000000467;

  // Stable Pool: wstETH, WETH (0.04%)
  // URL: https://app.balancer.fi/#/ethereum/pool/0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080
  bytes32 public poolIdWstETHStablePool = 0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;

  // Stable Pool: rETH, WETH (0.04%)
  // URL: https://app.balancer.fi/#/ethereum/pool/0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112
  bytes32 public poolIdRETHStablePool = 0x1e19cf2d73a72ef1332c882f20534b6519be0276000200000000000000000112;

  IVault public vault = IVault(VAULT);

  function testForkGetTokens() public {
    (
      IERC20[] memory tokens,
      , // uint256[] memory balances
      // uint256 lastChangeBlock
    ) = vault.getPoolTokens(poolIdWstETHStablePool);
    assertEq(address(tokens[0]), WSTETH);
  }

  // load user with 10k WSTETH, RETH
  function transferTokensLST(address _in) public {
    uint256 transferAmount = 1e22;
    vm.startPrank(RETH_RICHIE);
    IERC20(RETH).transfer(_in, transferAmount);
    vm.stopPrank();
    vm.startPrank(WSTETH_RICHIE);
    IERC20(WSTETH).transfer(_in, transferAmount);
    vm.stopPrank();
    assertEq(IERC20(RETH).balanceOf(_in), transferAmount);
    assertEq(IERC20(WSTETH).balanceOf(_in), transferAmount);
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
    // uint256 joinKind = uint256(ICronV1PoolEnums.JoinType.Join);
    bytes memory userData = getJoinUserData(uint256(ICronV1PoolEnums.JoinType.Join), _joinAmount0, _joinAmount1);
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    // stable pool paused, need to unpause
    vm.startPrank(ADMIN);
    ICronV1Pool(pool).setPause(false);
    vm.stopPrank();
    // IAsset[] memory assets = _convertERC20sToAssets(tokens);
    uint256[] memory maxAmountsIn = new uint256[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      maxAmountsIn[i] = type(uint256).max;
    }
    bool fromInternalBalance = false;
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
        fromInternalBalance
      )
    );
    assertGt(ICronV1Pool(pool).balanceOf(_in), 0);
    vm.stopPrank();
  }

  // forge test -vvvvv --fork-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY --match-test testForkFlashSwapWstethReth0
  // Long Term Swap: trading WSTETH for RETH
  // RETH overpriced, WSTETH underpriced in TWAMM pool
  // Sell WETH in TWAMM, buy WETH in Arb Pool
  // Note: need to calculate how much to swap, currently hardcoded for 10ETH
  function testForkFlashSwapWstethReth0() public {
    address alice = vm.addr(100);
    transferTokensLST(alice);
    // WSTETH: 5000
    // RETH: 4000
    joinPool(alice, WSTETH, RETH, 5e21, 4e21, uint256(ICronV1PoolEnums.PoolType.Liquid));
    vm.label(alice, "alice");
    vm.label(WSTETH, "WSTETH");
    vm.label(RETH, "RETH");
    vm.label(WETH, "WETH");
    vm.label(USDC, "USDC");
    // get pool from factory
    address pool = ICronV1PoolFactory(FACTORY).getPool(WSTETH, RETH, uint256(ICronV1PoolEnums.PoolType.Liquid));
    // console.log("Pool address", pool);
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    bytes memory userData = abi.encode(
      ICronV1PoolEnums.SwapType.RegularSwap, // swap type
      0
    );

    IERC20[] memory tokens = new IERC20[](3);
    tokens[0] = IERC20(RETH);
    tokens[1] = IERC20(WSTETH);
    tokens[2] = IERC20(WETH);

    // IAsset[] memory assets = _convertERC20sToAssets(tokens);
    int256[] memory limits = new int256[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      limits[i] = 0;
    }
    IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](3);
    // assetIn: RETH | assetOut: WSTETH
    // assertEq(RETH, address(tokens[getTokenIndex(RETH, poolId)]), "RETH Address correct");
    // assertEq(WSTETH, address(tokens[getTokenIndex(WSTETH, poolId)]), "WSTETH Address correct");
    swaps[0] = IVault.BatchSwapStep(
      poolId,
      getTokenIndex(RETH, tokens),
      getTokenIndex(WSTETH, tokens),
      1e18,
      userData
    );
    // assetIn: WSTETH | assetOut: USDC
    swaps[1] = IVault.BatchSwapStep(
      poolIdWstETHStablePool,
      getTokenIndex(WSTETH, tokens),
      getTokenIndex(WETH, tokens),
      0,
      ""
    );
    // assetIn: USDC | assetOut: RETH
    swaps[2] = IVault.BatchSwapStep(
      poolIdRETHStablePool,
      getTokenIndex(WETH, tokens),
      getTokenIndex(RETH, tokens),
      0,
      ""
    );
    // start acting as alice
    vm.startPrank(alice);
    // swap amounts with vault
    int256[] memory deltas = vault.batchSwap(
      IVault.SwapKind.GIVEN_IN,
      swaps,
      _convertERC20sToAssets(tokens),
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
    // assertLt(deltas[1], 0);
  }

  function testForkFlashSwapWstethReth1() public {
    address alice = vm.addr(100);
    transferTokensLST(alice);
    // WSTETH: 5000
    // RETH: 4000
    joinPool(alice, WSTETH, RETH, 5e21, 4e21, uint256(ICronV1PoolEnums.PoolType.Liquid));
    vm.label(alice, "alice");
    vm.label(WSTETH, "WSTETH");
    vm.label(RETH, "RETH");
    // get pool from factory
    address pool = ICronV1PoolFactory(FACTORY).getPool(WSTETH, RETH, uint256(ICronV1PoolEnums.PoolType.Liquid));
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    // setup information for short term swap through a TWAMM pool
    bytes memory userData = abi.encode(
      ICronV1PoolEnums.SwapType.RegularSwap, // swap type
      0
    );
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    (IERC20[] memory tokens2, , ) = vault.getPoolTokens(poolIdComposablePool);
    int256[] memory limits = new int256[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      limits[i] = 0;
    }
    // ensure correct tokens are in the pool for batchswap step
    assertEq(address(tokens[getTokenIndex(WSTETH, poolId)]), WSTETH, "WSTETH Check 1");
    assertEq(address(tokens[getTokenIndex(RETH, poolId)]), RETH, "RETH Check 1");
    assertEq(tokens2.length, 4, "Tokens length");
    assertEq(address(tokens2[getTokenIndex(WSTETH, poolIdComposablePool)]), WSTETH, "WSTETH Check 2");
    assertEq(address(tokens2[getTokenIndex(RETH, poolIdComposablePool)]), RETH, "RETH Check 2");
    IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](2);
    // assetIn: WSTETH (0) | assetOut: RETH (1)
    swaps[0] = IVault.BatchSwapStep(
      poolId,
      getTokenIndex(WSTETH, poolId),
      getTokenIndex(RETH, poolId),
      1e18,
      userData
    );
    // assetIn: RETH (3) | assetOut: WSTETH (1)
    swaps[1] = IVault.BatchSwapStep(
      poolIdComposablePool,
      getTokenIndex(RETH, poolIdComposablePool),
      getTokenIndex(WSTETH, poolIdComposablePool),
      0,
      ""
    );
    console.log("checking bounds for assets");
    console.log("checking bounds for assets2");
    checkSwapBounds(swaps, _convertERC20sToAssets(tokens));
    checkSwapBounds(swaps, _convertERC20sToAssets(tokens2));
    // start acting as alice
    vm.startPrank(alice);
    // swap amounts with vault
    vault.batchSwap(
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
    // console.log("Amount out: ", amountOut[0]);
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
        break;
      }
    }
  }

  function getTokenIndex(address _token, IERC20[] memory _tokens) public pure returns (uint256 index) {
    for (uint256 i = 0; i < _tokens.length; i++) {
      if (address(_tokens[i]) == _token) {
        index = i;
        break;
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
