// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {DeployALM} from "../common/DeployALM.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

contract DeployALMUNI is DeployALM {
    function setUp() public {
        loadActorsUNI();
        setup_network_specific_addresses_unichain();
        setup_oracles_params();
    }

    function run(bool isTestFeed) external {
        vm.startBroadcast(deployerKey);
        if (isTestFeed) deploy_oracle_with_test_feeds();
        else deploy_oracle();
        vm.stopBroadcast();

        saveOracleAddresses();
    }

    function setup_oracles_params() internal {
        // feedB = UConstants.chronicle_feed_USDC;
        // feedQ = UConstants.chronicle_feed_WETH;
        feedB = UConstants.api3_feed_USDC;
        feedQ = UConstants.api3_feed_WETH;
        stalenessThresholdB = 24 hours;
        stalenessThresholdQ = 24 hours;
        isInvertedPoolInOracle = false;
        decimalsDelta = int8(6) - int8(18);
    }
}
