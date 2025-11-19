// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** external imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {DeployALM} from "../common/DeployALM.sol";
import {ArbV4V4} from "@test/periphery/ArbV4V4.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

contract DeployArbitrageUNI is DeployALM {
    using PoolIdLibrary for PoolKey;

    PoolKey public arbitragePoolKey;

    function setUp() public {
        loadActorsUNI();
        setup_network_specific_addresses_unichain();
        setup_arbitrage_params();
        loadComponentAddresses();
    }

    function run(uint256 action) external {
        if (action == 0) {
            deploy_arbitrage();
        } else if (action == 5) {
            dealETH(arbitragerAddress, 10 ether);
            deploy_arbitrage();
        } else if (action == 1) {
            // Exclusive arbitrage with swap operator only
            loadArbitrageAdapterAddress();
            activate_arbitrage(address(arbitrageAdapter));
        } else if (action == 2) {
            // Non exclusive arbitrage
            loadArbitrageAdapterAddress();
            activate_arbitrage(address(0));
        } else if (action == 3) {
            // Calculate price ratio
            loadArbitrageAdapterAddress();
            (uint256 ratio, uint160 primarySqrtPrice, uint160 targetSqrtPrice) = arbitrageAdapter.calcPriceRatio();
            console.log("ratio: %s", ratio);
            console.log("primarySqrtPrice: %s", primarySqrtPrice);
            console.log("targetSqrtPrice: %s", targetSqrtPrice);
        } else if (action == 4) {
            // Align arbitrage
            loadArbitrageAdapterAddress();
            vm.startBroadcast(arbitragerKey);
            arbitrageAdapter.align();
            vm.stopBroadcast();
        } else revert("Invalid action");
    }

    function activate_arbitrage(address operator) internal {
        PoolId primaryPoolId = arbitrageAdapter.primaryPoolId();
        PoolId targetPoolId = arbitrageAdapter.targetPoolId();

        if (
            PoolId.unwrap(primaryPoolId) != PoolId.unwrap(poolKey.toId()) ||
            PoolId.unwrap(targetPoolId) != PoolId.unwrap(arbitragePoolKey.toId())
        ) {
            console.log("Arbitrage is not set for the given pools");
            vm.startBroadcast(arbitragerKey);
            arbitrageAdapter.setPools(poolKey, arbitragePoolKey);
            vm.stopBroadcast();
            console.log("Arbitrage is set!");
        }

        console.logBytes32(PoolId.unwrap(arbitrageAdapter.primaryPoolId()));
        console.logBytes32(PoolId.unwrap(arbitrageAdapter.targetPoolId()));

        if (hook.swapOperator() != operator) {
            console.log("Swap operator is not set for", operator);
            vm.startBroadcast(deployerKey);
            hook.setOperator(operator);
            vm.stopBroadcast();
            console.log("Swap operator is set!");
        }
    }

    function deploy_arbitrage() internal {
        console.log("Deploying Arbitrage");
        console.log("manager: %s", address(manager));

        vm.startBroadcast(arbitragerKey);
        arbitrageAdapter = new ArbV4V4(manager);
        vm.stopBroadcast();

        saveArbitrageAdapterAddresses();
    }

    function setup_arbitrage_params() internal {
        arbitragePoolKey = getAndCheckPoolKey(
            ETH,
            IERC20(UConstants.USDC),
            500,
            10,
            0x3258f413c7a88cda2fa8709a589d221a80f6574f63df5a5b6774485d8acc39d9
        );
    }
}
