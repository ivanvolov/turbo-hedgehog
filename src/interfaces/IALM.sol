// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IALM {
    error ZeroLiquidity();
    error ZeroDebt();
    error AddLiquidityThroughHook();
    error NotEnoughSharesToWithdraw();
    error NotZeroShares();
    error NotMinOutWithdraw();
    error BalanceInconsistency();
    error UnauthorizedPool();
    error SwapPriceChangeTooHigh();
    error NotALiquidityOperator();
    error NotASwapOperator();
    error OnlyOnePoolPerHook();

    event Deposit(address indexed to, uint256 amount, uint256 shares);
    event Withdraw(address indexed to, uint256 shares, uint256 amount0, uint256 amount1);

    function paused() external view returns (bool);

    function shutdown() external view returns (bool);

    function refreshReserves() external;

    function tickLower() external view returns (int24);

    function tickUpper() external view returns (int24);

    function updateBoundaries() external;

    function updateLiquidity(uint128 _liquidity) external;

    function sqrtPriceCurrent() external view returns (uint160);

    function isInvertedPool() external view returns (bool);

    function TVL() external view returns (uint256);

    function updateSqrtPrice(uint160 _sqrtPrice) external;

    function baseBalance(bool wrap) external view returns (uint256);

    function quoteBalance(bool wrap) external view returns (uint256);
}
