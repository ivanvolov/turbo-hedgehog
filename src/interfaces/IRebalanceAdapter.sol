// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IRebalanceAdapter {
    function sqrtPriceAtLastRebalance() external view returns (uint160);
}
