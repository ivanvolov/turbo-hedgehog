// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IOracle {
    function price() external view returns (uint256);

    function test_price() external view returns (uint256);

    function poolPrice() external view returns (uint256, uint256);
}
