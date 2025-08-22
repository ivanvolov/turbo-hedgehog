// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {ALMTestSimBase} from "@test/core/simulations/ALMTestSimBase.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ETH_ALMSimulationTest is ALMTestSimBase {
    using SafeERC20 for IERC20;

    IERC20 WETH = IERC20(MConstants.WETH);
    IERC20 USDC = IERC20(MConstants.USDC);

    function setUp() public {
        clear_snapshots();
        select_mainnet_fork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = MConstants.uniswap_v3_USDC_WETH_POOL;
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL); // 2652 usdc for eth (but in reversed tokens order)
        deployFreshManagerAndRouters();
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_euler_USDC_WETH();
        create_flash_loan_adapter_euler_USDC_WETH();
        create_oracle(MConstants.chainlink_feed_USDC, MConstants.chainlink_feed_WETH, true);
        init_hook(false, false, 0, 1e18, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            // hook.setNextLPFee(0); // By default, dynamic-fee-pools initialize with a 0% fee, to change - call rebalance.
            positionManager.setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalanceParams(6 * 1e17, 3 * 1e18, 2 * 1e18);
            rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
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
        hook.setNextLPFee(5000);
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
        (bool isRebalance, uint256 priceThreshold, uint256 auctionTriggerTime) = rebalanceAdapter.isRebalanceNeeded(
            oracle.price()
        );

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
            alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());
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
            delShares = alm.balanceOf(actor);
            alm.deposit(actor, amount, 0);
            balanceWETH = amount - WETH.balanceOf(actor);

            // ** Clear up account
            WETH.safeTransfer(zero.addr, WETH.balanceOf(actor));
            USDC.safeTransfer(zero.addr, USDC.balanceOf(actor));

            delShares = alm.balanceOf(actor) - delShares;
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
        uint256 shares1 = (alm.balanceOf(actor) * sharesPercent * 1e16) / 1e18;
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
            uint256 sharesBefore = alm.balanceOf(actor);
            alm.withdraw(actor, shares1, 0, 0);
            assertEq(sharesBefore - alm.balanceOf(actor), shares1);

            balanceWETH = WETH.balanceOf(actor);
            balanceUSDC = USDC.balanceOf(actor);

            // ** Clear up account
            WETH.safeTransfer(zero.addr, WETH.balanceOf(actor));
            USDC.safeTransfer(zero.addr, USDC.balanceOf(actor));
        }

        save_withdraw_data(shares1, shares2, actor, balanceWETH, balanceUSDC, balanceWETHcontrol, balanceUSDCcontrol);
        vm.stopPrank();

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());
    }
}
