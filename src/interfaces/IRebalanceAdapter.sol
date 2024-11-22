// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IRebalanceAdapter {
    function withdraw(uint256 deltaDebt, uint256 deltaCollateral) external;
}
