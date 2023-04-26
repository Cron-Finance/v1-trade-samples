pragma solidity ^0.7.6;

pragma experimental ABIEncoderV2;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import "forge-std/StdUtils.sol";

import { IERC20 } from "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IAsset } from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import { IWETH } from "@balancer-labs/v2-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { IWStETH } from "../src/interfaces/IWStETH.sol";
import { ICronV1Pool } from "../src/interfaces/ICronV1Pool.sol";
import { ICronV1PoolEnums } from "../src/interfaces/pool/ICronV1PoolEnums.sol";
import { ICronV1PoolFactory } from "../src/interfaces/ICronV1PoolFactory.sol";

// forge test -vvvvv --fork-url https://eth-mainnet.g.alchemy.com/v2/$ALCHEMY_API_KEY --match-path test/NounsDAOTest.t.sol

contract NounsDAOTest is Test {
  address public constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
  address public constant FACTORY = 0xD64c9CD98949C07F3C85730a37c13f4e78f35E77;

  address public constant NOUNS_DAO = 0x0BC3807Ec262cB779b38D65b38158acC3bfedE10;

  address public constant DELEGATE = 0x29c5dad7E34d0A27d6F65a0A7E07E4d03Dcd68c8;

  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
  address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
  address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

  // address with a lot of tokens
  address public constant WETH_RICHIE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
  address public constant USDC_RICHIE = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
  address public constant RETH_RICHIE = 0x7C5aaA2a20b01df027aD032f7A768aC015E77b86;
  address public constant WSTETH_RICHIE = 0x248cCBf4864221fC0E840F29BB042ad5bFC89B5c;

  IVault public vault = IVault(VAULT);
  
  // load user with 10k WSTETH, RETH
  function transferTokens(address _in) public {
    uint256 transferAmount = 1e22; //10,000
    vm.startPrank(RETH_RICHIE);
    IERC20(RETH).transfer(_in, transferAmount);
    vm.stopPrank();
    vm.startPrank(WSTETH_RICHIE);
    IERC20(WSTETH).transfer(_in, transferAmount);
    vm.stopPrank();
    assertEq(IERC20(RETH).balanceOf(_in), transferAmount);
    assertEq(IERC20(WSTETH).balanceOf(_in), transferAmount);
  }

  function joinPool(address _in, address _token0, address _token1, uint256 _poolType) public {
    uint256 joinAmount = 5e21; // 5,000
    // get pool from factory
    address pool = ICronV1PoolFactory(FACTORY).getPool(_token0, _token1, _poolType);
    // console.log("Pool address", pool);
    // setup information for pool join
    uint256 joinKind = uint256(ICronV1PoolEnums.JoinType.Join);
    bytes memory userData = getJoinUserData(joinKind, joinAmount, joinAmount);
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    (IERC20[] memory tokens, , ) = vault.getPoolTokens(poolId);
    // IAsset[] memory assets = _convertERC20sToAssets(tokens);
    uint256[] memory maxAmountsIn = new uint256[](tokens.length);
    for (uint256 i; i < tokens.length; i++) {
      maxAmountsIn[i] = type(uint256).max;
    }
    bool fromInternalBalance = false;
    // check LP tokens for _in is 0
    assertEq(ICronV1Pool(pool).balanceOf(_in), 0);
    // check token balances
    assertGt(IERC20(_token0).balanceOf(_in), joinAmount, "inufficient token0");
    assertGt(IERC20(_token1).balanceOf(_in), joinAmount, "insufficient token1");
    // start acting as _in
    vm.startPrank(_in);
    // approve tokens to be used by vault
    IERC20(tokens[0]).approve(VAULT, joinAmount);
    IERC20(tokens[1]).approve(VAULT, joinAmount);
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

  function testForkNounsDAODiversifcation() public {
    address liquidityProvider = vm.addr(100);
    // transfer tokens to liquidityProvider
    transferTokens(liquidityProvider);
    // add liquidity to TWAMM pool
    joinPool(liquidityProvider, WSTETH, RETH, uint256(ICronV1PoolEnums.PoolType.Stable));
    // get pool from factory
    address pool = ICronV1PoolFactory(FACTORY).getPool(WSTETH, RETH, uint256(ICronV1PoolEnums.PoolType.Stable));
    // setup information for short term swap through a TWAMM pool
    uint256 swapAmount = 450e18;
    uint256 intervals = 675;
    // setup information for long term swap
    bytes memory userData = abi.encode(
      ICronV1PoolEnums.SwapType.LongTermSwap, // swap type
      intervals
    );
    bytes32 poolId = ICronV1Pool(pool).POOL_ID();
    (IERC20[] memory tokens, , ) = IVault(VAULT).getPoolTokens(poolId);
    IAsset[] memory assets = _convertERC20sToAssets(tokens);
    vm.startPrank(NOUNS_DAO);
    // approve stETH to be wrapped
    IERC20(STETH).approve(WSTETH, swapAmount);
    // wrap stETH to wstETH: roughly 450 stETH ~ 400 wstETH
    uint256 wrappedAmount = IWStETH(WSTETH).wrap(swapAmount);
    // approve tokens to spend from this contract in the vault
    tokens[0].approve(VAULT, wrappedAmount);
    // send long term order request to the pool via vault
    IVault(VAULT).swap(
      IVault.SingleSwap(poolId, IVault.SwapKind.GIVEN_IN, assets[0], assets[1], wrappedAmount, userData),
      IVault.FundManagement(NOUNS_DAO, false, payable(DELEGATE), false),
      0,
      block.timestamp + 1000
    );
    vm.stopPrank();
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
