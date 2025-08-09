// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** interfaces
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";

/// @notice Interface for all standard position manager setters.
interface IPositionManagerStandard is IPositionManager {
    function setKParams(uint256 _k1, uint256 _k2) external;
}
