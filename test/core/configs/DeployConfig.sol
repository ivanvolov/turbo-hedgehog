// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
        uint24 feeLP;
        uint160 swapPriceThreshold;
    }

    struct KParams {
        uint256 k1;
        uint256 k2;
    }

    struct Config {
        RebalanceParams preDeployParams;
        RebalanceParams params;
        RebalanceConstraints preDeployConstraints;
        RebalanceConstraints constraints;
        HookParams hookParams;
        KParams kParams;
    }
}
