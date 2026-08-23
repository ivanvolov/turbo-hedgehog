// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {DeployALM} from "../common/DeployALM.sol";
import {TestFeed} from "@test/simulations/TestFeed.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

contract DeployOraclesUNI is DeployALM {
    function setUp() public {
        loadActorsUNI();
        setup_network_specific_addresses_unichain();
        setup_oracles_params();
    }

    function run(uint256 action) external {
        console.log("Deploying Oracles");
        console.log("Block.timestamp", block.timestamp);
        vm.startBroadcast(deployerKey);
        if (action == 0) {
            // Test Mock feeds
            feedB = new TestFeed(999801391481903400, 18);
            feedQ = new TestFeed(3854785066950000000000, 18);
            deploy_oracle();
        } else if (action == 1) {
            // Chronicle feeds
            feedB = UConstants.chronicle_feed_USDC;
            feedQ = UConstants.chronicle_feed_WETH;
            deploy_oracle();
        } else if (action == 2) {
            // API3 feeds
            feedB = UConstants.api3_feed_USDC;
            feedQ = UConstants.api3_feed_WETH;
            deploy_oracle();
        } else revert("Invalid action");
        vm.stopBroadcast();

        saveOracleAddresses();
    }

    function setup_oracles_params() internal {
        stalenessThresholdB = 24 hours;
        stalenessThresholdQ = 24 hours;
        isInvertedPoolInOracle = false;
        decimalsDelta = int8(6) - int8(18);
    }
}
