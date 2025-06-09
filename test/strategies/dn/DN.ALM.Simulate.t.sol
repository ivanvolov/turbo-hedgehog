// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {ALMTestSimBase} from "@test/core/ALMTestSimBase.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";

contract DeltaNeutralALMSimulationTest is ALMTestSimBase {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    IERC20 WETH = IERC20(TestLib.WETH);
    IERC20 USDC = IERC20(TestLib.USDC);

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
        create_lending_adapter_euler_WETH_USDC();
        create_flash_loan_adapter_euler_WETH_USDC();
        create_oracle(true, TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC, 1 hours, 10 hours);
        init_hook(true, false, 0, 1e18, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            IPositionManagerStandard(address(positionManager)).setFees(0);
            IPositionManagerStandard(address(positionManager)).setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalanceParams(45 * 1e16, 3 * 1e18, 3 * 1e18); // 0.45 (45%)
            rebalanceAdapter.setRebalanceConstraints(1e15, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        init_control_hook();

        approve_accounts();
        deal(address(USDC), address(swapper.addr), 100_000_000 * 1e6);
        deal(address(WETH), address(swapper.addr), 100_000 * 1e18);
    }

    function test_swaps_simulation() public {
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(50000); // 5%
        numberOfSwaps = 10; // Number of blocks with swaps
        resetGenerator();

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
        if (isRebalance) {
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
        vm.startPrank(actor);

        uint256 delShares;
        {
            deal(address(USDC), actor, amount);
            delShares = hook.balanceOf(actor);
            hook.deposit(actor, amount, 0);
            delShares = hook.balanceOf(actor) - delShares;
        }

        save_deposit_data(amount, actor, 0, 0, 0, delShares, 0);
        vm.stopPrank();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());
    }
}
