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

contract DeployALMUNI is DeployALM {
    PoolKey public ETH_USDC_key_unichain;

    function setUp() public {
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

    function run(bool isAnvilTestRun) external {
        if (isAnvilTestRun) {
            console.log("Dealing ETH");
            dealETH(deployerAddress, 10 ether);
        }

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

        saveComponentAddresses(false);
    }

    function setup_strategy_params() internal {
        TOKEN_NAME = "Turbo HH";
        TOKEN_SYMBOL = "TURBO";
        BASE = IERC20(UConstants.USDC);
        QUOTE = IERC20(UConstants.WETH);
        decimalsDelta = int8(6) - int8(18);
        longLeverage = 3e18;
        shortLeverage = 2e18;
        weight = 55e16; //50%
        liquidityMultiplier = 2e18;
        slippage = 15e14; //0.15%
        feeLP = 500; //0.05%
        initialSQRTPrice = Constants.SQRT_PRICE_1_1;

        IS_NTS = true;
        isInvertedAssets = false;
        isInvertedPool = false;
        isNova = false;

        protocolFee = 0;
        tvlCap = 1000 ether;
        tickLowerDelta = 3000;
        tickUpperDelta = 3000;
        swapPriceThreshold = TestLib.SQRT_PRICE_10PER;

        k1 = 1425 * 1e15; //1.425
        k2 = 1425 * 1e15; //1.425
        treasury = 0x3A1e87139D73CD4a931888B755625246c1038B65;
        rebalanceOperator = deployerAddress;
        swapOperator = address(0);
        liquidityOperator = address(0);
        rebalancePriceThreshold = TestLib.ONE_PERCENT_AND_ONE_BPS;
        rebalanceTimeThreshold = 2000;
        maxDeviationLong = 1e17;
        maxDeviationShort = 1e17;

        //! This is deposit mode only values.
        {
            longLeverage = 2e18;
            shortLeverage = 1e18;
            weight = 1e18;
            swapOperator = deployerAddress;
        }
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
