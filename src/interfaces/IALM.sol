// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IALM {
    error ZeroLiquidity();
    error ZeroDebt();
    error AddLiquidityThroughHook();
    error NotEnoughSharesToWithdraw();
    error NotZeroShares();
    error NotMinOutWithdrawBase();
    error NotMinOutWithdrawQuote();
    error BalanceInconsistency();
    error UnauthorizedPool();
    error SwapPriceChangeTooHigh();
    error NotALiquidityOperator();
    error NotASwapOperator();
    error OnlyOnePoolPerHook();
    error TVLCapExceeded();
    error NotAValidPositionState();

    event Deposit(address indexed to, uint256 amount, uint256 delShares, uint256 TVL, uint256 totalSupply);
    event Withdraw(
        address indexed to,
        uint256 delShares,
        uint256 baseOut,
        uint256 quoteOut,
        uint256 TVL,
        uint256 totalSupply,
        uint256 liquidity
    );
    event HookSwap(
        bytes32 indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint128 hookLPfeeAmount0,
        uint128 hookLPfeeAmount1
    );
    event HookFee(bytes32 indexed id, address indexed sender, uint128 feeAmount0, uint128 feeAmount1);

    function paused() external view returns (bool);

    function shutdown() external view returns (bool);

    function refreshReserves() external;

    function transferFees() external;

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
