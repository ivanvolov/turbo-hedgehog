// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestLib} from "@test/libraries/TestLib.sol";
import {DeployConfig} from "./DeployConfig.sol";

library TurboDeployConfig {
    function getConfig() internal pure returns (DeployConfig.Config memory) {
        return
            DeployConfig.Config({
                preDeployParams: DeployConfig.RebalanceParams({weight: 9e17, longLeverage: 2e18, shortLeverage: 1e18}),
                params: DeployConfig.RebalanceParams({weight: 525e15, longLeverage: 3e18, shortLeverage: 2e18}),
                preDeployConstraints: DeployConfig.RebalanceConstraints({
                    rebalancePriceThreshold: TestLib.ONE_PERCENT_AND_ONE_BPS, // 1.01%
                    rebalanceTimeThreshold: 2000,
                    maxDeviationLong: 1e17,
                    maxDeviationShort: 1e17
                }),
                constraints: DeployConfig.RebalanceConstraints({
                    rebalancePriceThreshold: 1e17, //price change threshold
                    rebalanceTimeThreshold: 60 * 60 * 24 * 4, // 4 days
                    maxDeviationLong: 1e17, //max deviation long leverage position
                    maxDeviationShort: 1e17 //max deviation short leverage position
                }),
                hookParams: DeployConfig.HookParams({
                    isInvertedAssets: false,
                    isInvertedPool: false,
                    isNova: false,
                    liquidityMultiplier: 2e18,
                    protocolFee: 0,
                    tvlCap: 1000 ether,
                    tickLowerDelta: 3000,
                    tickUpperDelta: 3000,
                    feeLP: 1,
                    swapPriceThreshold: uint160(TestLib.SQRT_PRICE_10PER)
                }),
                kParams: DeployConfig.KParams({
                    k1: 1425 * 1e15, // 1.425
                    k2: 1425 * 1e15 // 1.425
                })
            });
    }
}
