// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {ALMTestSimBase} from "@test/core/ALMTestSimBase.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";

contract ETHALMSimulationTest is ALMTestSimBase {
    using SafeERC20 for IERC20;

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
        create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC, 1 hours, 10 hours);
        init_hook(true, false, 3000, 3000);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setIsInvertAssets(false);
            hook.setTVLCap(1000 ether);
            hook.setSwapPriceThreshold(TestLib.sqrt_price_10per_price_change);
            hook.setProtocolFee(0);
            hook.setTreasury(treasury.addr);
            IPositionManagerStandard(address(positionManager)).setFees(0);
            IPositionManagerStandard(address(positionManager)).setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setIsInvertAssets(false);
            rebalanceAdapter.setRebalancePriceThreshold(1e15);
            rebalanceAdapter.setRebalanceTimeThreshold(60 * 60 * 24 * 7);
            rebalanceAdapter.setWeight(6 * 1e17); // 0.6 (60%)
            rebalanceAdapter.setLongLeverage(3 * 1e18); // 3
            rebalanceAdapter.setShortLeverage(2 * 1e18); // 2
            rebalanceAdapter.setMaxDeviationLong(1e17); // 0.1 (1%)
            rebalanceAdapter.setMaxDeviationShort(1e17); // 0.1 (1%)
            vm.stopPrank();
        }

        init_control_hook();

        approve_accounts();
        deal(address(USDC), address(swapper.addr), 100_000_000 * 1e6);
        deal(address(WETH), address(swapper.addr), 100_000 * 1e18);
    }

    function test_simulation() public {
        depositProbabilityPerBlock = 10; // Probability of deposit per block
        maxDeposits = 5; // The maximum number of deposits. Set to max(uint256) to disable

        withdrawProbabilityPerBlock = 7; // Probability of withdraw per block
        maxWithdraws = 3; // The maximum number of withdraws. Set to max(uint256) to disable

        numberOfSwaps = 50; // Number of blocks with swaps

        maxUniqueDepositors = 5; // The maximum number of depositors
        depositorReuseProbability = 50; // 50 % prob what the depositor will be reused rather then creating new one

        resetGenerator();
        uint256 depositsRemained = maxDeposits;
        uint256 withdrawsRemained = maxWithdraws;

        uint256 randomAmount;

        // ** First deposit to allow swapping
        {
            approve_actor(alice.addr);
            deposit(1000 ether, alice.addr);
            save_pool_state();
            rollOneBlock();
        }

        // ** Do rebalance cause no swaps before first rebalance
        {
            try_rebalance();
            save_pool_state();
            rollOneBlock();
        }

        // ** Do random swaps with periodic deposits and withdraws
        for (uint i = 0; i < numberOfSwaps; i++) {
            // **  Always do swaps
            {
                randomAmount = random(10) * 1e18;
                bool zeroForOne = (random(2) == 1);
                bool _in = (random(2) == 1);

                // Now will adjust amount if it's USDC goes In
                if ((zeroForOne && _in) || (!zeroForOne && !_in)) randomAmount = (randomAmount * getHookPrice()) / 1e30;

                simulate_swap(randomAmount, zeroForOne, _in, true);
                save_pool_state();
            }

            // ** Do random deposits
            if (depositsRemained > 0) {
                randomAmount = random(100);
                if (randomAmount <= depositProbabilityPerBlock) {
                    randomAmount = random(10);
                    address actor = chooseDepositor();
                    deposit(randomAmount * 1e18, actor);
                    save_pool_state();
                    depositsRemained--;
                }
            }

            // ** Do random withdraws
            if (withdrawsRemained > 0) {
                randomAmount = random(100);
                if (randomAmount <= withdrawProbabilityPerBlock) {
                    address actor = getDepositorToReuse();
                    if (actor != address(0)) {
                        randomAmount = random(100); // It is percent here

                        withdraw(randomAmount, actor);
                        save_pool_state();
                        withdrawsRemained--;
                    }
                }
            }

            // ** Roll block after each iteration
            rollOneBlock();
        }

        // ** Withdraw all remaining liquidity
        {
            for (uint id = 1; id <= lastGeneratedAddressId; id++) {
                withdraw(100, getDepositorById(id));
                save_pool_state();
            }

            withdraw(100, alice.addr);
            save_pool_state();
        }
    }

    function test_rebalance_simulation() public {
        numberOfSwaps = 10; // Number of blocks with swaps

        resetGenerator();

        uint256 randomAmount;

        // ** First deposit to allow swapping
        {
            approve_actor(alice.addr);
            deposit(1000 ether, alice.addr);
            save_pool_state();
            rollOneBlock();
        }

        // ** Do rebalance cause no swaps before first rebalance
        {
            try_rebalance();
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

                simulate_swap(randomAmount, zeroForOne, _in, true);
                save_pool_state();
            }

            // ** Always try to do rebalance
            try_rebalance();
            save_pool_state();

            // ** Roll block after each iteration
            rollOneBlock();
        }

        withdraw(100, alice.addr);
        save_pool_state();
    }

    function test_swaps_simulation() public {
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e16);
        numberOfSwaps = 10; // Number of blocks with swaps

        resetGenerator();

        uint256 randomAmount;

        // ** First deposit to allow swapping
        {
            approve_actor(alice.addr);
            deposit(1000 ether, alice.addr);
            save_pool_state();
            rollOneBlock();
        }

        // ** Do rebalance cause no swaps before first rebalance
        {
            try_rebalance();
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

    function try_rebalance() internal {
        (bool isRebalance, uint256 priceThreshold, uint256 auctionTriggerTime) = rebalanceAdapter.isRebalanceNeeded();

        if (isRebalance) {
            {
                vm.startPrank(rebalanceAdapter.owner());
                bool success = _rebalanceOrError(1e15);
                if (!success) success = _rebalanceOrError(1e16);
                if (!success) success = _rebalanceOrError(1e17);
                vm.stopPrank();
            }

            vm.prank(swapper.addr);
            hookControl.rebalance();

            save_rebalance_data(priceThreshold, auctionTriggerTime);

            // ** Make oracle change with swap price
            alignOraclesAndPools(hook.sqrtPriceCurrent());
        }
    }

    function deposit(uint256 amount, address actor) internal {
        vm.startPrank(actor);

        uint256 balanceWETHcontrol;
        uint256 balanceUSDCcontrol;
        uint256 delSharesControl;

        {
            deal(address(WETH), actor, amount);
            deal(address(USDC), actor, amount / 1e8); // should be 1e12 but gor 4 zeros to be sure
            delSharesControl = hookControl.balanceOf(actor);
            hookControl.deposit(amount);
            balanceWETHcontrol = amount - WETH.balanceOf(actor);
            balanceUSDCcontrol = amount / 1e8 - USDC.balanceOf(actor);

            // ** Clear up account
            WETH.safeTransfer(zero.addr, WETH.balanceOf(actor));
            USDC.safeTransfer(zero.addr, USDC.balanceOf(actor));

            delSharesControl = hookControl.balanceOf(actor) - delSharesControl;
        }

        uint256 balanceWETH;
        uint256 delShares;
        {
            deal(address(WETH), actor, amount);
            delShares = hook.balanceOf(actor);
            hook.deposit(actor, amount);
            balanceWETH = amount - WETH.balanceOf(actor);

            // ** Clear up account
            WETH.safeTransfer(zero.addr, WETH.balanceOf(actor));
            USDC.safeTransfer(zero.addr, USDC.balanceOf(actor));

            delShares = hook.balanceOf(actor) - delShares;
        }

        save_deposit_data(
            amount,
            actor,
            balanceWETH,
            balanceWETHcontrol,
            balanceUSDCcontrol,
            delShares,
            delSharesControl
        );
        vm.stopPrank();
    }

    function withdraw(uint256 sharesPercent, address actor) internal {
        uint256 shares1 = (hook.balanceOf(actor) * sharesPercent * 1e16) / 1e18;
        uint256 shares2 = (hookControl.balanceOf(actor) * sharesPercent * 1e16) / 1e18;

        vm.startPrank(actor);

        uint256 balanceWETHcontrol;
        uint256 balanceUSDCcontrol;

        {
            uint256 sharesBefore = hookControl.balanceOf(actor);
            hookControl.withdraw(shares2);
            assertEq(sharesBefore - hookControl.balanceOf(actor), shares2);

            balanceWETHcontrol = WETH.balanceOf(actor);
            balanceUSDCcontrol = USDC.balanceOf(actor);

            // ** Clear up account
            WETH.safeTransfer(zero.addr, WETH.balanceOf(actor));
            USDC.safeTransfer(zero.addr, USDC.balanceOf(actor));
        }

        uint256 balanceWETH;
        uint256 balanceUSDC;
        {
            uint256 sharesBefore = hook.balanceOf(actor);
            hook.withdraw(actor, shares1, 0, 0);
            assertEq(sharesBefore - hook.balanceOf(actor), shares1);

            balanceWETH = WETH.balanceOf(actor);
            balanceUSDC = USDC.balanceOf(actor);

            // ** Clear up account
            WETH.safeTransfer(zero.addr, WETH.balanceOf(actor));
            USDC.safeTransfer(zero.addr, USDC.balanceOf(actor));
        }

        save_withdraw_data(shares1, shares2, actor, balanceWETH, balanceUSDC, balanceWETHcontrol, balanceUSDCcontrol);
        vm.stopPrank();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());
    }
}
