// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRebalanceAdapter {
    function sqrtPriceAtLastRebalance() external view returns (uint160);
}
