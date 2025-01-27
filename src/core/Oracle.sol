// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";

contract Oracle is IOracle {
    function price() external pure returns (uint256) {
        return 3849 * 1e18; //TODO: oracle
    }
}
