// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";
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

contract ALMTest is MorphoTestBase {
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
        approve_accounts();
        presetChainlinkOracles();
    }

    function test_hook_deployment_exploit_revert() public {
        vm.expectRevert();
        (key, ) = initPool(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            hook,
            poolFee + 1,
            initialSQRTPrice
        );
    }

    function test_aave_lending_adapter_long() public {
        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        lendingAdapter.addAuthorizedCaller(address(alice.addr));

        // ** Approve to Morpho
        vm.startPrank(alice.addr);
        WETH.approve(address(lendingAdapter), type(uint256).max);
        USDC.approve(address(lendingAdapter), type(uint256).max);

        // ** Add collateral
        uint256 wethToSupply = 1e18;
        deal(address(WETH), address(alice.addr), wethToSupply);
        lendingAdapter.addCollateralLong(wethToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Borrow
        uint256 usdcToBorrow = ((wethToSupply * 3843) / 1e12) / 2;
        lendingAdapter.borrowLong(ALMBaseLib.c6to18(usdcToBorrow));
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), ALMBaseLib.c6to18(usdcToBorrow), 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToBorrow);

        // ** Repay
        lendingAdapter.repayLong(ALMBaseLib.c6to18(usdcToBorrow));
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Remove collateral
        lendingAdapter.removeCollateralLong(wethToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceState(alice.addr, wethToSupply, 0);

        vm.stopPrank();
    }

    function test_aave_lending_adapter_short() public {
        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        lendingAdapter.addAuthorizedCaller(address(alice.addr));

        // ** Approve to LA
        vm.startPrank(alice.addr);
        WETH.approve(address(lendingAdapter), type(uint256).max);
        USDC.approve(address(lendingAdapter), type(uint256).max);

        // ** Add collateral
        uint256 usdcToSupply = 3843 * 1e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.addCollateralShort(ALMBaseLib.c6to18(usdcToSupply));
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), ALMBaseLib.c6to18(usdcToSupply), 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Borrow
        uint256 wethToBorrow = ((usdcToSupply * 1e12) / 3843) / 2;
        lendingAdapter.borrowShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), ALMBaseLib.c6to18(usdcToSupply), 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), wethToBorrow, 1e1);
        assertEqBalanceState(alice.addr, wethToBorrow, 0);

        // ** Repay
        lendingAdapter.repayShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), ALMBaseLib.c6to18(usdcToSupply), 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Remove collateral
        lendingAdapter.removeCollateralShort(ALMBaseLib.c6to18(usdcToSupply));
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToSupply);

        vm.stopPrank();
    }

    uint256 amountToDep = 100 ether;

    function test_withdraw() public {
        vm.expectRevert(IALM.NotZeroShares.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 0, 0);

        vm.expectRevert(IALM.NotEnoughSharesToWithdraw.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 10, 0);
    }

    function test_deposit() public {
        assertEq(hook.TVL(), 0);

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        (, uint256 shares) = hook.deposit(alice.addr, amountToDep);
        assertApproxEqAbs(shares, amountToDep, 1e10);
        assertEq(hook.balanceOf(alice.addr), shares);

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(amountToDep, 0, 0, 0);

        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice);
        assertApproxEqAbs(hook.TVL(), amountToDep, 1e4);
    }

    function test_deposit_withdraw() public {
        test_deposit();

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.expectRevert(IALM.ZeroDebt.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0);
    }

    uint256 slippage = 1e15;

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

    function test_deposit_rebalance_withdraw() public {
        test_deposit_rebalance();
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0);
        assertEq(hook.balanceOf(alice.addr), 0);

        assertEqBalanceState(alice.addr, 99620659279839587529, 0);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(hook.TVL(), 0, 1e4);
        assertEqBalanceStateZero(address(hook));
    }

    function test_deposit_rebalance_withdraw_revert_min_eth() public {
        test_deposit_rebalance();
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.expectRevert(IALM.NotMinETHWithdraw.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, amountToDep);
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        test_deposit_rebalance();
        uint256 usdcToSwap = 3843 * 1e6;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 998527955338248048, 1e4);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(178577097663642993432, 307919999998, 458498879999, 39615625618981243890);

        assertEq(hook.sqrtPriceCurrent(), 1276210418792347117463625826499913);
        assertApproxEqAbs(hook.TVL(), 99 * 1e18, 1e18);
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        uint256 usdcToSwapQ = 3848673309; // this should be get from quoter
        uint256 wethToGetFSwap = 1 ether;
        test_deposit_rebalance();

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 1 ether, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(178574999999999996901, 307919999998, 458493206690, 39614999999999999310);

        assertEq(hook.sqrtPriceCurrent(), 1276207798475351959769149392702478);
        assertApproxEqAbs(hook.TVL(), 99 * 1e18, 1e18);
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        uint256 wethToSwap = 1 ether;
        test_deposit_rebalance();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 3837966928);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(181424999999999996902, 307919999998, 466179846927, 40464999999999999310);

        assertEq(hook.sqrtPriceCurrent(), 1279767903767319294406366522471430);
        assertApproxEqAbs(hook.TVL(), 99 * 1e18, 1e18);
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        uint256 wethToSwapQ = 999999999764801051; // this should be get from quoter
        uint256 usdcToGetFSwap = 3837966928;
        test_deposit_rebalance();

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(181424999999999996902, 307919999998, 466179846927, 40464999999900039757);

        assertEq(hook.sqrtPriceCurrent(), 1279767903766900627896346016900868);
        assertApproxEqAbs(hook.TVL(), 99 * 1e18, 1e18);
    }

    function test_deposit_rebalance_swap_rebalance() public {
        test_deposit_rebalance();

        {
            // ** Swap some more
            uint256 usdcToSwap = 3843 * 1e6 * 20;

            deal(address(USDC), address(swapper.addr), usdcToSwap);
            assertEqBalanceState(swapper.addr, 0, usdcToSwap);

            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
            // assertApproxEqAbs(deltaWETH, 998527955338248048, 1e4);

            assertEqBalanceState(swapper.addr, deltaWETH, 0);
            assertEqBalanceState(address(hook), 0, 0);
        }

        {
            // ** Second rebalance
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);

            assertEqBalanceStateZero(address(hook));
            // assertEqPositionState(180 * 1e18, 307919 * 1e6, 462341 * 1e6, 40039999999999999310);
            assertApproxEqAbs(hook.TVL(), 100191841810579074801, 1e18);
        }
    }

    function test_empty_rebalance() public {}

    // function test_swap_price_down_rebalance_withdraw() public {
    //     test_swap_price_down_rebalance();

    //     uint256 shares = hook.balanceOf(alice.addr);
    //     assertEqBalanceStateZero(alice.addr);
    //     assertApproxEqAbs(shares, 100 ether, 1e10);

    //     vm.prank(alice.addr);
    //     hook.withdraw(alice.addr, shares / 2);

    //     assertApproxEqAbs(hook.balanceOf(alice.addr), shares / 2, 1e10);
    //     assertEqBalanceState(alice.addr, 49478363633548016058, 0);
    // }

    // function test_swap_price_down_withdraw() public {
    //     test_swap_price_down_in();

    //     uint256 shares = hook.balanceOf(alice.addr);
    //     assertEqBalanceStateZero(alice.addr);
    //     assertApproxEqAbs(shares, 100 ether, 1e10);

    //     vm.prank(alice.addr);
    //     hook.withdraw(alice.addr, shares / 10);

    //     // assertApproxEqAbs(hook.balanceOf(alice.addr), shares / 2, 1e10);
    //     // assertEqBalanceState(alice.addr, 49478363633548016058, 0);
    // }

    // function test_swap_price_up_withdraw() public {
    //     test_swap_price_up_in();

    //     uint256 shares = hook.balanceOf(alice.addr);
    //     assertEqBalanceStateZero(alice.addr);
    //     assertApproxEqAbs(shares, 100 ether, 1e10);

    //     vm.prank(alice.addr);
    //     hook.withdraw(alice.addr, shares / 2);

    //     assertApproxEqAbs(hook.balanceOf(alice.addr), shares / 2, 1e10);
    //     assertEqBalanceState(alice.addr, 49525627778055050818, 2243500000);
    // }

    function test_lending_adapter_migration() public {
        // test_swap_price_down_rebalance();
        // // This is better to do after rebalance
        // vm.startPrank(deployer.addr);
        // ILendingAdapter newAdapter = new AaveLendingAdapter();
        // newAdapter.setShortMId(shortMId);
        // newAdapter.setLongMId(longMId);
        // newAdapter.addAuthorizedCaller(address(hook));
        // newAdapter.addAuthorizedCaller(address(rebalanceAdapter));
        // // @Notice: Alice here acts as a migration contract the purpose of with is to transfer collateral between adapters
        // newAdapter.addAuthorizedCaller(alice.addr);
        // rebalanceAdapter.setLendingAdapter(address(newAdapter));
        // hook.setLendingAdapter(address(newAdapter));
        // lendingAdapter.addAuthorizedCaller(address(alice.addr));
        // vm.stopPrank();
        // uint256 collateral = lendingAdapter.getCollateral();
        // vm.startPrank(alice.addr);
        // lendingAdapter.removeCollateral(collateral);
        // WETH.approve(address(newAdapter), type(uint256).max);
        // newAdapter.addCollateral(collateral);
        // vm.stopPrank();
        // assertEqBalanceState(address(hook), 0, 0);
        // assertEqMorphoA(shortMId, address(newAdapter), 0, 0, 0);
        // assertEqMorphoA(longMId, address(newAdapter), 0, 0, 98956727267096030628);
    }

    function test_accessability() public {
        vm.expectRevert(SafeCallback.NotPoolManager.selector);
        hook.afterInitialize(address(0), key, 0, 0);

        vm.expectRevert(IALM.AddLiquidityThroughHook.selector);
        hook.beforeAddLiquidity(address(0), key, IPoolManager.ModifyLiquidityParams(0, 0, 0, ""), "");

        PoolKey memory failedKey = key;
        failedKey.tickSpacing = 3;

        vm.expectRevert(IALM.UnauthorizedPool.selector);
        hook.beforeAddLiquidity(address(0), failedKey, IPoolManager.ModifyLiquidityParams(0, 0, 0, ""), "");

        vm.expectRevert(SafeCallback.NotPoolManager.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");

        vm.expectRevert(IALM.UnauthorizedPool.selector);
        hook.beforeSwap(address(0), failedKey, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_pause() public {
        vm.prank(deployer.addr);
        hook.setPaused(true);

        vm.expectRevert(IALM.ContractPaused.selector);
        hook.deposit(address(0), 0);

        vm.expectRevert(IALM.ContractPaused.selector);
        hook.withdraw(deployer.addr, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(IALM.ContractPaused.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_shutdown() public {
        vm.prank(deployer.addr);
        hook.setShutdown(true);

        vm.expectRevert(IALM.ContractShutdown.selector);
        hook.deposit(deployer.addr, 0);

        vm.prank(address(manager));
        vm.expectRevert(IALM.ContractShutdown.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }
}
