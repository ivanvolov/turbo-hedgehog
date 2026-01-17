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
import {DeployConfig} from "./DeployConfig.sol";

// ** interfaces
import {IOracleTest} from "@test/interfaces/IOracleTest.sol";

contract DeployALMUNI is DeployALM {
    PoolKey public ETH_USDC_key_unichain;
    DeployConfig.Config internal config;

    function setUp() public {
        config = DeployConfig.getConfig();
        loadActorsUNI();
        setup_network_specific_addresses_unichain();
        setup_strategy_params();
        setup_adapters_params();
        loadOracleAddress();

        ETH_USDC_key_unichain = getAndCheckPoolKey(
            ETH,
            IERC20(UConstants.USDC),
            500,
            10,
            0x3258f413c7a88cda2fa8709a589d221a80f6574f63df5a5b6774485d8acc39d9
        );
    }

    function run(bool transferETHToDeployer, bool isPreDepositMode) external {
        if (transferETHToDeployer) {
            console.log("Dealing ETH");
            dealETH(deployerAddress, 10 ether);
        }

        if (isPreDepositMode) setup_params_on_pre_deposit_mode();

        // ** Deploy adapters
        {
            vm.startBroadcast(deployerKey);
            deploy_fl_adapter_morpho();
            deploy_lending_adapter_euler();
            deploy_position_manager();
            vm.stopBroadcast();
        }

        deploy_and_init_hook();

        // ** Setting up strategy params
        {
            vm.startBroadcast(deployerKey);
            hook.setTreasury(treasury);
            positionManager.setKParams(k1, k2);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(
                rebalancePriceThreshold,
                rebalanceTimeThreshold,
                maxDeviationLong,
                maxDeviationShort
            );
            uint8[4] memory config = [0, 1, 2, 3];
            setSwapAdapterToV4SingleSwap(ETH_USDC_key_unichain, config);
            vm.stopBroadcast();
        }

        saveComponentAddresses();
    }

    function setup_strategy_params() internal {
        TOKEN_NAME = "Turbo HH PD";
        TOKEN_SYMBOL = "TURBO PD";
        BASE = IERC20(UConstants.USDC);
        QUOTE = IERC20(UConstants.WETH);
        longLeverage = config.params.longLeverage;
        shortLeverage = config.params.shortLeverage;
        weight = config.params.weight;
        liquidityMultiplier = config.hookParams.liquidityMultiplier;
        initialSQRTPrice = Constants.SQRT_PRICE_1_1;

        IS_NTS = true;
        isInvertedAssets = config.hookParams.isInvertedAssets;
        isInvertedPool = config.hookParams.isInvertedPool;
        isNova = config.hookParams.isNova;

        protocolFee = config.hookParams.protocolFee;
        tvlCap = config.hookParams.tvlCap;
        tickLowerDelta = config.hookParams.tickLowerDelta;
        tickUpperDelta = config.hookParams.tickUpperDelta;
        swapPriceThreshold = config.hookParams.swapPriceThreshold;

        k1 = config.kParams.k1;
        k2 = config.kParams.k2;
        treasury = 0x3A1e87139D73CD4a931888B755625246c1038B65;
        rebalanceOperator = deployerAddress;
        swapOperator = address(0);
        liquidityOperator = address(0);
        rebalancePriceThreshold = config.constraints.rebalancePriceThreshold;
        rebalanceTimeThreshold = config.constraints.rebalanceTimeThreshold;
        maxDeviationLong = config.constraints.maxDeviationLong;
        maxDeviationShort = config.constraints.maxDeviationShort;
    }

    function setup_params_on_pre_deposit_mode() internal {
        swapOperator = deployerAddress;
        weight = config.preDeployParams.weight;
        longLeverage = config.preDeployParams.longLeverage;
        shortLeverage = config.preDeployParams.shortLeverage;
        rebalancePriceThreshold = config.preDeployConstraints.rebalancePriceThreshold;
        rebalanceTimeThreshold = config.preDeployConstraints.rebalanceTimeThreshold;
        maxDeviationLong = config.preDeployConstraints.maxDeviationLong;
        maxDeviationShort = config.preDeployConstraints.maxDeviationShort;
    }

    function setup_adapters_params() internal {
        morpho = UConstants.MORPHO;
        ethereumVaultConnector = UConstants.EULER_VAULT_CONNECT;
        vault0 = UConstants.eulerUSDCVault1;
        vault1 = UConstants.eulerWETHVault1;
        merklRewardsDistributor = UConstants.merklRewardsDistributor;
        rEUL = UConstants.rEUL;
    }
}
