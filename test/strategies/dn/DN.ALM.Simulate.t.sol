// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// ** v4 imports
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {ALMControl} from "@test/core/ALMControl.sol";
import {ALMTestSimBase} from "@test/core/ALMTestSimBase.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";

contract DeltaNeutralALMSimulationTest is ALMTestSimBase {
    using PoolIdLibrary for PoolId;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    TestERC20 WETH = TestERC20(TestLib.WETH);
    TestERC20 USDC = TestERC20(TestLib.USDC);

    function setUp() public {
        clear_snapshots();

        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_WETH_USDC_POOL;
            assertEqPSThresholdCL = 1e5;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e5;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL); // 2652 usdc for eth (but in reversed tokens order)
        deployFreshManagerAndRouters();
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler(
            TestLib.eulerUSDCVault1,
            0,
            TestLib.eulerWETHVault1,
            0,
            TestLib.eulerUSDCVault2,
            0,
            TestLib.eulerWETHVault2,
            0
        );
        create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC);
        init_hook(true, false);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setIsInvertAssets(true);
            // hook.setIsInvertedPool(?); // @Notice: this is already set in the init_hook, cause it's needed on initialize
            hook.setSwapPriceThreshold(1e18);
            rebalanceAdapter.setIsInvertAssets(true);
            IPositionManagerStandard(address(positionManager)).setFees(0);
            IPositionManagerStandard(address(positionManager)).setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalancePriceThreshold(1e15); //10% price change
            rebalanceAdapter.setRebalanceTimeThreshold(2000);
            rebalanceAdapter.setWeight(45 * 1e16); // 0.45 (45%)
            rebalanceAdapter.setLongLeverage(3 * 1e18); // 3
            rebalanceAdapter.setShortLeverage(3 * 1e18); // 3
            rebalanceAdapter.setMaxDeviationLong(1e17); // 0.01 (1%)
            rebalanceAdapter.setMaxDeviationShort(1e17); // 0.01 (1%)
            vm.stopPrank();
        }

        init_control_hook();

        approve_accounts();
        deal(address(USDC), address(swapper.addr), 100_000_000 * 1e6);
        deal(address(WETH), address(swapper.addr), 100_000 * 1e18);
    }

    function test_swaps_simulation() public {
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e16);
        numberOfSwaps = 10; // Number of blocks with swaps

        resetGenerator();
        console.log("Simulation started");
        console.log(block.timestamp);
        console.log(block.number);

        uint256 randomAmount;

        // ** First deposit to allow swapping
        {
            approve_actor(alice.addr);
            deposit(10000 * 1e6, alice.addr);
            save_pool_state();
            rollOneBlock();
        }

        // ** Do rebalance cause no swaps before first rebalance
        {
            try_rebalance(false);
            save_pool_state();
            rollOneBlock();
        }

        for (uint i = 0; i < numberOfSwaps; i++) {
            // **  Always do swaps
            {
                randomAmount = random(10) * 1e18;
                bool zeroForOne = (random(2) == 1);
                bool _in = (random(2) == 1);

                // Now will adjust amount if it's USDC goes In
                if ((zeroForOne && _in) || (!zeroForOne && !_in)) randomAmount = (randomAmount * getHookPrice()) / 1e30;

                simulate_swap(randomAmount, zeroForOne, _in, false);
                save_pool_state();
            }

            // ** Roll block after each iteration
            rollOneBlock();
        }
    }

    function try_rebalance(bool rebalanceControl) internal {
        (bool isRebalance, uint256 priceThreshold, uint256 auctionTriggerTime) = rebalanceAdapter.isRebalanceNeeded();
        console.log(">> isRebalance", isRebalance);
        if (isRebalance) {
            console.log(">> doing rebalance");
            {
                vm.startPrank(rebalanceAdapter.owner());
                bool success = _rebalanceOrError(1e15);
                if (!success) success = _rebalanceOrError(1e16);
                if (!success) success = _rebalanceOrError(1e17);
                vm.stopPrank();
            }

            if (rebalanceControl) {
                vm.prank(swapper.addr);
                hookControl.rebalance();
            }

            save_rebalance_data(priceThreshold, auctionTriggerTime);

            // ** Make oracle change with swap price
            alignOraclesAndPools(hook.sqrtPriceCurrent());
        }
    }

    function deposit(uint256 amount, address actor) internal {
        console.log(">> do deposit:", actor, amount);
        vm.startPrank(actor);

        uint256 delShares;
        {
            deal(address(USDC), actor, amount);
            delShares = hook.balanceOf(actor);
            hook.deposit(actor, amount);
            delShares = hook.balanceOf(actor) - delShares;
        }

        save_deposit_data(amount, actor, 0, 0, 0, delShares, 0);
        vm.stopPrank();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());
    }
}
