// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Defines the interface for an Automated Liquidity Manager.
interface IALM {
    error ZeroLiquidity();
    error ZeroDebt();
    error AddLiquidityThroughHook();
    error NotZeroShares();
    error NotMinOutWithdrawBase();
    error NotMinOutWithdrawQuote();
    error BalanceInconsistency();
    error UnauthorizedPool();
    error SwapPriceChangeTooHigh();
    error NotALiquidityOperator();
    error NotASwapOperator();
    error MustUseDynamicFee();
    error TVLCapExceeded();
    error NotAValidPositionState();
    error NotMinShares();
    error ProtocolFeeNotValid();
    error LiquidityMultiplierNotValid();
    error TicksMisordered(int24 tickLower, int24 tickUpper);
    error TickLowerOutOfBounds(int24 tick);
    error TickUpperOutOfBounds(int24 tick);
    error TickDeltasNotValid();
    error LPFeeTooLarge(uint24 fee);

    event StatusSet(uint8 indexed status);
    event OperatorsSet(address indexed liquidityOperator, address indexed swapOperator);
    event TreasurySet(address indexed treasury);
    event ProtocolParamsSet(
        uint256 liquidityMultiplier,
        uint256 protocolFee,
        uint256 tvlCap,
        uint256 swapPriceThreshold,
        int24 tickLowerDelta,
        int24 tickUpperDelta
    );
    event LiquidityUpdated(uint128 newLiquidity);
    event SqrtPriceUpdated(uint160 newSqrtPrice);
    event BoundariesUpdated(int24 newTickLower, int24 newTickUpper);
    event Deposit(address indexed to, uint256 amount, uint256 delShares, uint256 TVL, uint256 totalSupply);
    event Withdraw(
        address indexed to,
        uint256 delShares,
        uint256 baseOut,
        uint256 quoteOut,
        uint256 totalSupply,
        uint256 liquidity
    );
    event LPFeeSet(uint24 fee);
    event HookFee(bytes32 indexed id, address indexed sender, uint128 feeAmount0, uint128 feeAmount1);

    struct Ticks {
        int24 lower;
        int24 upper;
    }

    function activeTicks() external view returns (int24 lower, int24 upper);

    function tickDeltas() external view returns (int24 lower, int24 upper);

    function status() external view returns (uint8);

    function refreshReservesAndTransferFees() external;

    function updateLiquidityAndBoundariesToOracle() external;

    function updateLiquidityAndBoundaries(uint160 sqrtPrice) external returns (uint128 newLiquidity);

    function isInvertedPool() external view returns (bool);

    function TVL(uint256 price) external view returns (uint256);

    function protocolFee() external view returns (uint256);
}
