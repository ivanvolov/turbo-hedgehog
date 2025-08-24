// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// ** contracts
import {TestOracle} from "@test/simulations/TestOracle.sol";

contract DeployOracleSimulation is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("TEST_ANVIL_PRIVATE_KEY_DEPLOYER");

        // Start broadcasting transactions
        vm.startBroadcast(deployerKey);

        // Deploy TestOracle
        TestOracle oracle = new TestOracle();
        console.log("TestOracle deployed at:", address(oracle));

        vm.stopBroadcast();
    }
}
