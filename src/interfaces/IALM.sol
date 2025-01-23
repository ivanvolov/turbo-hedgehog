// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** libraries
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";

interface IALM {
    error ZeroLiquidity();
    error ZeroDebt();
    error NotHookDeployer();
    error NotRebalanceAdapter();
    error AddLiquidityThroughHook();
    error ContractPaused();
    error ContractShutdown();
    error NotEnoughSharesToWithdraw();
    error NotZeroShares();
    error NotMinOutWithdraw();
    error BalanceInconsistency();
    error UnauthorizedPool();

    event Deposit(address indexed to, uint256 amount, uint256 shares);
    event Withdraw(address indexed to, uint256 shares, uint256 amount0, uint256 amount1);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function t0Dec() external view returns (uint8);

    function t1Dec() external view returns (uint8);

    function refreshReserves() external;

    function oracle() external view returns (IOracle);

    function tickLower() external view returns (int24);

    function tickUpper() external view returns (int24);

    function updateBoundaries() external;

    function updateLiquidity(uint128 _liquidity) external;

    function sqrtPriceCurrent() external view returns (uint160);

    function TVL() external view returns (uint256);

    function token0Balance(bool wrap) external view returns (uint256);

    function token1Balance(bool wrap) external view returns (uint256);
}
