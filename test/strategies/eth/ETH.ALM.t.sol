// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";
import {ALM} from "@src/ALM.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {AaveLendingAdapter} from "@src/core/lendingAdapters/AaveLendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IALM} from "@src/interfaces/IALM.sol";

contract ETHALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);

        initialSQRTPrice = getPoolSQRTPrice(ALMBaseLib.ETH_USDC_POOL); // 3843 usdc for eth (but in reversed tokens order)

        deployFreshManagerAndRouters();

        create_accounts_and_tokens();
        init_hook();

        // Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setInvertAssets(false);
            positionManager.setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalancePriceThreshold(1e18);
            rebalanceAdapter.setRebalanceTimeThreshold(2000);
            rebalanceAdapter.setWeight(6 * 1e17); // 0.6 (60%)
            rebalanceAdapter.setLongLeverage(3 * 1e18); // 3
            rebalanceAdapter.setShortLeverage(2 * 1e18); // 2
            rebalanceAdapter.setMaxDeviationLong(1e16); // 0.01 (1%)
            rebalanceAdapter.setMaxDeviationShort(1e16); // 0.01 (1%)
            vm.stopPrank();
        }

        approve_accounts();
        presetChainlinkOracles();
    }

    function test_withdraw() public {
        vm.expectRevert(IALM.NotZeroShares.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 0, 0);

        vm.expectRevert(IALM.NotEnoughSharesToWithdraw.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 10, 0);
    }

    uint256 amountToDep = 100 ether;

    function test_deposit() public {
        assertEq(hook.TVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        (, uint256 shares) = hook.deposit(alice.addr, amountToDep);
        assertEq(shares, amountToDep, "shares returned");
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(amountToDep, 0, 0, 0);

        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertEq(hook.TVL(), amountToDep, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_withdraw_revert() public {
        test_deposit();

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.expectRevert(IALM.ZeroDebt.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0);
    }

    uint256 slippage = 1e16;

    function test_deposit_rebalance() public {
        test_deposit();

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);

        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(180 * 1e18, 307919 * 1e6, 462341 * 1e6, 40039999999999999310);
        assertApproxEqAbs(hook.TVL(), 99 * 1e18, 1e18);
    }

    // function test_deposit_rebalance_revert_no_rebalance_needed() public {
    //     test_deposit();

    //     vm.prank(deployer.addr);
    //     rebalanceAdapter.rebalance(slippage);

    //     vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
    //     vm.prank(deployer.addr);
    //     rebalanceAdapter.rebalance(slippage);
    // }

    // function test_deposit_rebalance_withdraw() public {
    //     test_deposit_rebalance();
    //     assertEqBalanceStateZero(alice.addr);

    //     uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
    //     vm.prank(alice.addr);
    //     hook.withdraw(alice.addr, sharesToWithdraw, 0);
    //     assertEq(hook.balanceOf(alice.addr), 0);

    //     assertEqBalanceState(alice.addr, 99620659279839587529, 0);
    //     assertEqPositionState(0, 0, 0, 0);
    //     assertApproxEqAbs(hook.TVL(), 0, 1e4);
    //     assertEqBalanceStateZero(address(hook));
    // }

    // function test_deposit_rebalance_withdraw_revert_min_eth() public {
    //     test_deposit_rebalance();
    //     assertEqBalanceStateZero(alice.addr);

    //     uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
    //     vm.expectRevert(IALM.NotMinOutWithdraw.selector);
    //     vm.prank(alice.addr);
    //     hook.withdraw(alice.addr, sharesToWithdraw, amountToDep);
    // }

    // function test_deposit_rebalance_swap_price_up_in() public {
    //     test_deposit_rebalance();
    //     uint256 usdcToSwap = 3843 * 1e6;

    //     deal(address(USDC), address(swapper.addr), usdcToSwap);
    //     assertEqBalanceState(swapper.addr, 0, usdcToSwap);

    //     (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
    //     assertApproxEqAbs(deltaWETH, 998527955338248048, 1e4);

    //     assertEqBalanceState(swapper.addr, deltaWETH, 0);
    //     assertEqBalanceState(address(hook), 0, 0);

    //     assertEqPositionState(178577097663642993432, 307919999998, 458498879999, 39615625618981243890);

    //     assertEq(hook.sqrtPriceCurrent(), 1276210418792347117463625826499913);
    //     assertApproxEqAbs(hook.TVL(), 99 * 1e18, 1e18);
    // }

    // function test_deposit_rebalance_swap_price_up_out() public {
    //     uint256 usdcToSwapQ = 3848673309; // this should be get from quoter
    //     uint256 wethToGetFSwap = 1 ether;
    //     test_deposit_rebalance();

    //     deal(address(USDC), address(swapper.addr), usdcToSwapQ);
    //     assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

    //     (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
    //     assertApproxEqAbs(deltaWETH, 1 ether, 1e1);

    //     assertEqBalanceState(swapper.addr, deltaWETH, 0);
    //     assertEqBalanceState(address(hook), 0, 0);

    //     assertEqPositionState(178574999999999996901, 307919999998, 458493206690, 39614999999999999310);

    //     assertEq(hook.sqrtPriceCurrent(), 1276207798475351959769149392702478);
    //     assertApproxEqAbs(hook.TVL(), 99 * 1e18, 1e18);
    // }

    // function test_deposit_rebalance_swap_price_down_in() public {
    //     uint256 wethToSwap = 1 ether;
    //     test_deposit_rebalance();

    //     deal(address(WETH), address(swapper.addr), wethToSwap);
    //     assertEqBalanceState(swapper.addr, wethToSwap, 0);

    //     (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
    //     assertEq(deltaUSDC, 3837966928);

    //     assertEqBalanceState(swapper.addr, 0, deltaUSDC);
    //     assertEqBalanceState(address(hook), 0, 0);

    //     assertEqPositionState(181424999999999996902, 307919999998, 466179846927, 40464999999999999310);

    //     assertEq(hook.sqrtPriceCurrent(), 1279767903767319294406366522471430);
    //     assertApproxEqAbs(hook.TVL(), 99 * 1e18, 1e18);
    // }

    // function test_deposit_rebalance_swap_price_down_out() public {
    //     uint256 wethToSwapQ = 999999999764801051; // this should be get from quoter
    //     uint256 usdcToGetFSwap = 3837966928;
    //     test_deposit_rebalance();

    //     deal(address(WETH), address(swapper.addr), wethToSwapQ);
    //     assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

    //     (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
    //     assertEq(deltaUSDC, usdcToGetFSwap);

    //     assertEqBalanceState(swapper.addr, 0, deltaUSDC);
    //     assertEqBalanceState(address(hook), 0, 0);

    //     assertEqPositionState(181424999999999996902, 307919999998, 466179846927, 40464999999900039757);

    //     assertEq(hook.sqrtPriceCurrent(), 1279767903766900627896346016900868);
    //     assertApproxEqAbs(hook.TVL(), 99 * 1e18, 1e18);
    // }

    // function test_deposit_rebalance_swap_rebalance() public {
    //     test_deposit_rebalance();

    //     {
    //         // ** Swap some more
    //         uint256 usdcToSwap = 3843 * 1e6 * 20;

    //         deal(address(USDC), address(swapper.addr), usdcToSwap);
    //         assertEqBalanceState(swapper.addr, 0, usdcToSwap);

    //         (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
    //         // assertApproxEqAbs(deltaWETH, 998527955338248048, 1e4);

    //         assertEqBalanceState(swapper.addr, deltaWETH, 0);
    //         assertEqBalanceState(address(hook), 0, 0);
    //     }

    //     {
    //         // ** Second rebalance
    //         vm.prank(deployer.addr);
    //         rebalanceAdapter.rebalance(slippage);

    //         assertEqBalanceStateZero(address(hook));
    //         // assertEqPositionState(180 * 1e18, 307919 * 1e6, 462341 * 1e6, 40039999999999999310);
    //         assertApproxEqAbs(hook.TVL(), 100191841810579074801, 1e18);
    //     }
    // }
}
