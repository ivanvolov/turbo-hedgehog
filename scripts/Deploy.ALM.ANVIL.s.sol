// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// ** external imports
import {Constants} from "v4-core-test/utils/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {DeployALM} from "./common/DeployALM.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {TestLib} from "@test/libraries/TestLib.sol";

contract DeployALMAnvil is DeployALM, Script {
    function setUp() public {
        deployerKey = vm.envUint("TEST_ANVIL_PRIVATE_KEY");
        setup_network_specific_addresses();
        setup_strategy_params();
        setup_adapters_params();
    }

    function run() external {
        vm.startBroadcast(deployerKey);

        deploy_fl_adapter_morpho();
        deploy_lending_adapter_euler();
        deploy_oracle();
        deploy_position_manager();

        deploy_and_init_hook();

        vm.stopBroadcast();
    }

    function setup_network_specific_addresses() internal {
        PERMIT_2 = UConstants.PERMIT_2;
        WETH9 = UConstants.WETH9;
        manager = UConstants.manager;
        universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER;
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
        isInvertedPoolInOracle = false;
        isNova = false;

        protocolFee = 0;
        tvlCap = 1000 ether;
        tickLowerDelta = 3000;
        tickUpperDelta = 3000;
        swapPriceThreshold = TestLib.sqrt_price_10per;
    }

    function setup_adapters_params() internal {
        feedB = UConstants.chronicle_feed_USDC;
        feedQ = UConstants.chronicle_feed_WETH;
        stalenessThresholdB = 24 hours;
        stalenessThresholdQ = 24 hours;
        morpho = UConstants.MORPHO;

        ethereumVaultConnector = UConstants.EULER_VAULT_CONNECT;
        vault0 = UConstants.eulerUSDCVault1;
        vault1 = UConstants.eulerWETHVault1;
        merklRewardsDistributor = UConstants.merklRewardsDistributor;
        rEUL = UConstants.rEUL;
    }
}
