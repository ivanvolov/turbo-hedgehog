// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** external imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Constants} from "v4-core-test/utils/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {DeployALM} from "../common/DeployALM.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {TestLib} from "@test/libraries/TestLib.sol";

// ** interfaces
import {IOracleTest} from "@test/interfaces/IOracleTest.sol";

contract MoveALMUNI is DeployALM {
    PoolKey public ETH_USDC_key_unichain;

    function setUp() public {
        setup_network_specific_addresses_unichain();
        BASE = IERC20(UConstants.USDC);
        QUOTE = IERC20(UConstants.WETH);
        loadActorsUNI();
        loadComponentAddresses();
    }

    function run() external {
        // TODO: this should be redo according to PRE_DEPOSIT_UNI_ALMTest
        longLeverage = 3e18;
        shortLeverage = 2e18;
        weight = 55e16; //50%

        vm.startBroadcast(deployerKey);
        alm.setStatus(1); // paused

        rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
        baseStrategyHook.setOperator(address(0));

        alm.setStatus(0); // active

        vm.stopBroadcast();
    }
}
