// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestLib} from "@test/libraries/TestLib.sol";

library DeployConfig {
    struct RebalanceParams {
        uint256 weight;
        uint256 longLeverage;
        uint256 shortLeverage;
    }

    struct RebalanceConstraints {
        uint256 rebalancePriceThreshold;
        uint256 rebalanceTimeThreshold;
        uint256 maxDeviationLong;
        uint256 maxDeviationShort;
    }

    struct HookParams {
        bool isInvertedAssets;
        bool isInvertedPool;
        bool isNova;
        uint256 liquidityMultiplier;
        uint256 protocolFee;
        uint256 tvlCap;
        int24 tickLowerDelta;
        int24 tickUpperDelta;
        uint160 swapPriceThreshold;
    }

    struct KParams {
        uint256 k1;
        uint256 k2;
    }

    struct Config {
        RebalanceParams preDeployParams;
        RebalanceConstraints preDeployConstraints;
        RebalanceParams params;
        RebalanceConstraints constraints;
        HookParams hookParams;
        KParams kParams;
    }

    function getConfig() internal pure returns (Config memory) {
        return
            Config({
                preDeployParams: RebalanceParams({weight: 9e17, longLeverage: 2e18, shortLeverage: 1e18}),
                params: RebalanceParams({weight: 525e15, longLeverage: 3e18, shortLeverage: 2e18}),
                preDeployConstraints: RebalanceConstraints({
                    rebalancePriceThreshold: TestLib.ONE_PERCENT_AND_ONE_BPS, // 1.01%
                    rebalanceTimeThreshold: 2000,
                    maxDeviationLong: 1e17,
                    maxDeviationShort: 1e17
                }),
                constraints: RebalanceConstraints({
                    rebalancePriceThreshold: 1e17, //price change threshold
                    rebalanceTimeThreshold: 60 * 60 * 24 * 4, // 4 days
                    maxDeviationLong: 1e17, //max deviation long leverage position
                    maxDeviationShort: 1e17 //max deviation short leverage position
                }),
                hookParams: HookParams({
                    isInvertedAssets: false,
                    isInvertedPool: false,
                    isNova: false,
                    liquidityMultiplier: 2e18,
                    protocolFee: 0,
                    tvlCap: 1000 ether,
                    tickLowerDelta: 3000,
                    tickUpperDelta: 3000,
                    swapPriceThreshold: uint160(TestLib.SQRT_PRICE_10PER)
                }),
                kParams: KParams({
                    k1: 1425 * 1e15, // 1.425
                    k2: 1425 * 1e15 // 1.425
                })
            });
    }
}
