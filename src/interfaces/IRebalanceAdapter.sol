// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IRebalanceAdapter {
    function sqrtPriceAtLastRebalance() external view returns (uint160);

    function oraclePriceAtLastRebalance() external view returns (uint256);

    function calcLiquidity() external view returns (uint128);
}
