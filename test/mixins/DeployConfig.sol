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
        uint256 priceThreshold;
        uint256 timeThreshold;
        uint256 maxDeviationLong;
        uint256 maxDeviationShort;
    }

    struct HookParams {
        bool isInvertedPool;
        bool isSourcePool;
        uint256 liquidityMultiplier;
        uint256 liquidity;
        uint256 initialToken0;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
    }

    struct KParams {
        uint256 kLower;
        uint256 kUpper;
    }

    struct Config {
        RebalanceParams initialParams;
        RebalanceConstraints initialConstraints;
        RebalanceParams lifecycleParams;
        RebalanceConstraints lifecycleConstraints;
        HookParams hookParams;
        KParams kParams;
    }

    function getConfig() internal pure returns (Config memory) {
        return
            Config({
                initialParams: RebalanceParams({weight: 9e17, longLeverage: 2e18, shortLeverage: 1e18}),
                initialConstraints: RebalanceConstraints({
                    priceThreshold: TestLib.ONE_PERCENT_AND_ONE_BPS, // 1.01%
                    timeThreshold: 2000,
                    maxDeviationLong: 1e17,
                    maxDeviationShort: 1e17
                }),
                lifecycleParams: RebalanceParams({weight: 525e15, longLeverage: 3e18, shortLeverage: 2e18}),
                lifecycleConstraints: RebalanceConstraints({
                    priceThreshold: 1e17, //price change threshold
                    timeThreshold: 60 * 60 * 24 * 4, // 4 days
                    maxDeviationLong: 1e17, //max deviation long leverage position
                    maxDeviationShort: 1e17 //max deviation short leverage position
                }),
                hookParams: HookParams({
                    isInvertedPool: false,
                    isSourcePool: false,
                    liquidityMultiplier: 2e18,
                    liquidity: 0,
                    initialToken0: 1000 ether,
                    tickLower: 3000,
                    tickUpper: 3000,
                    sqrtPriceX96: uint160(TestLib.SQRT_PRICE_10PER)
                }),
                kParams: KParams({
                    kLower: 1425 * 1e15, // 1.425
                    kUpper: 1425 * 1e15 // 1.425
                })
            });
    }
}
