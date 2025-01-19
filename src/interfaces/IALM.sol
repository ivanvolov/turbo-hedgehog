// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

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

    function refreshReserves() external;

    function oracle() external view returns (IOracle);

    function tickLower() external view returns (int24);

    function tickUpper() external view returns (int24);

    function rebalanceAdapter() external view returns (address);

    function updateBoundaries() external;

    function sqrtPriceCurrent() external view returns (uint160);

    function TVL() external view returns (uint256);
}
