// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Defines the interface for an Automated Liquidity Manager.
interface IALM {
    error ZeroLiquidity();
    error NotZeroShares();
    error NotMinOutWithdrawBase();
    error NotMinOutWithdrawQuote();
    error NotALiquidityOperator();
    error TVLCapExceeded();
    error NotAValidPositionState();
    error NotMinShares();

    event StatusSet(uint8 indexed status);
    event OperatorSet(address indexed liquidityOperator);
    event TVLCapSet(uint256 tvlCap);
    event Deposit(address indexed to, uint256 amount, uint256 delShares, uint256 TVL, uint256 totalSupply);
    event Withdraw(
        address indexed to,
        uint256 delShares,
        uint256 baseOut,
        uint256 quoteOut,
        uint256 totalSupply,
        uint256 liquidity
    );

    function status() external view returns (uint8);

    function TVL(uint256 price) external view returns (uint256);
}
