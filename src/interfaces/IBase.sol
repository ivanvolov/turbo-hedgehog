// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";

interface IBase {
    function oracle() external view returns (IOracle);

    function setTokens(address _token0, address _token1, uint8 _t0Dec, uint8 _t1Dec) external;

    function setComponents(
        address _alm,
        address _lendingAdapter,
        address _positionManager,
        address _oracle,
        address _rebalanceAdapter
    ) external;

    function transferOwnership(address newOwner) external;
}
