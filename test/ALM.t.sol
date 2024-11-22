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
import {MorphoLendingAdapter} from "@src/core/MorphoLendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IALM} from "@src/interfaces/IALM.sol";

contract ALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        initialSQRTPrice = 1182773400228691521900860642689024; // 4487 usdc for eth (but in reversed tokens order). Tick: 192228

        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);

        deployFreshManagerAndRouters();

        create_accounts_and_tokens();
        create_and_seed_morpho_markets();
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
            initialSQRTPrice,
            ""
        );
    }

    function test_morpho_lending_adapter_supply() public {
        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        lendingAdapter.addAuthorizedCaller(address(alice.addr));

        vm.startPrank(alice.addr);

        // ** Approve to Morpho
        USDC.approve(address(lendingAdapter), type(uint256).max);

        // ** Supply
        uint256 usdcToSupply = 4000 * 1e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.supply(usdcToSupply);

        assertEqMorphoS(depositUSDCmId, usdcToSupply * 1e6, 0, 0);
        assertEqBalanceStateZero(alice.addr);

        // ** Withdraw
        lendingAdapter.withdraw(usdcToSupply);
        assertEqMorphoS(borrowUSDCmId, 0, 0, 0);
        assertEqBalanceState(alice.addr, 0, usdcToSupply);

        vm.stopPrank();
    }

    function test_morpho_lending_adapter_borrow() public {
        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        lendingAdapter.addAuthorizedCaller(address(alice.addr));

        vm.startPrank(alice.addr);

        // ** Approve to Morpho
        WETH.approve(address(lendingAdapter), type(uint256).max);
        USDC.approve(address(lendingAdapter), type(uint256).max);

        // ** Supply collateral
        deal(address(WETH), address(alice.addr), 1 ether);
        lendingAdapter.addCollateral(1 ether);

        assertEqMorphoS(borrowUSDCmId, 0, 0, 1 ether);
        assertEqBalanceStateZero(alice.addr);

        // ** Borrow
        uint256 borrowUSDC = 4000 * 1e6;
        lendingAdapter.borrow(borrowUSDC);

        assertEqMorphoS(borrowUSDCmId, 0, borrowUSDC * 1e6, 1 ether);
        assertEqBalanceState(alice.addr, 0, borrowUSDC);

        // ** Repay
        lendingAdapter.repay(borrowUSDC);
        assertEqMorphoS(borrowUSDCmId, 0, 0, 1 ether);
        assertEqBalanceStateZero(alice.addr);

        // ** Withdraw collateral
        lendingAdapter.removeCollateral(1 ether);
        assertEqMorphoS(borrowUSDCmId, 0, 0, 0);
        assertEqBalanceState(alice.addr, 1 ether, 0);

        vm.stopPrank();
    }

    // function test_volatility_fees() public {
    //     assertEq(hook.getSwapFees(), 1149360638297872);
    // }

    uint256 amountToDep = 100 ether;

    function test_deposit() public {
        assertEq(hook.TVL(), 0);

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        (, uint256 shares) = hook.deposit(alice.addr, amountToDep);
        assertApproxEqAbs(shares, amountToDep, 1e10);

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqMorphoA(borrowUSDCmId, 0, 0, amountToDep);
        assertEqMorphoA(depositUSDCmId, 0, 0, 0);

        assertEq(hook.sqrtPriceCurrent(), 1182773400228691521900860642689024);
        assertEq(hook._calcCurrentPrice(), 4486999999999999769339);
        assertApproxEqAbs(hook.TVL(), amountToDep, 1e10);
    }

    function test_swap_price_up_in() public {
        uint256 usdcToSwap = 4487 * 1e6;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 948744443889899008, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, usdcToSwap, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, 0, amountToDep - deltaWETH);

        assertEq(hook.sqrtPriceCurrent(), 1181210201945000124313491613764168);
    }

    function test_swap_price_up_out() public {
        uint256 usdcToSwapQ = 4469867134; // this should be get from quoter
        uint256 wethToGetFSwap = 1 ether;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 1 ether, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, usdcToSwapQ, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, 0, amountToDep - deltaWETH);

        assertEq(hook.sqrtPriceCurrent(), 1184338667228746981679537543072454);
    }

    function test_swap_price_down_in() public {
        uint256 wethToSwap = 1 ether;
        test_deposit();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 4257016319);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, deltaUSDC, amountToDep + wethToSwap);

        assertEq(hook.sqrtPriceCurrent(), 1184338667228746981679537543072454);
    }

    function test_swap_price_down_out() public {
        uint256 wethToSwapQ = 1048539297596844510; // this should be get from quoter
        uint256 usdcToGetFSwap = 4486999802;
        test_deposit();

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqMorphoA(depositUSDCmId, 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, deltaUSDC, amountToDep + wethToSwapQ);

        assertEq(hook.sqrtPriceCurrent(), 1181128042874516412352801494904863);
    }

    function test_swap_price_down_rebalance() public {
        test_swap_price_down_in();

        vm.expectRevert();
        rebalanceAdapter.rebalance();

        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        rebalanceAdapter.rebalance();

        // Swap some more
        uint256 wethToSwap = 10 * 1e18;
        deal(address(WETH), address(swapper.addr), wethToSwap);
        swapWETH_USDC_In(wethToSwap);

        assertEq(hook.sqrtPriceCurrent(), 1199991337229301579466306546906758);

        assertEqBalanceState(address(hook), 0, 0);
        assertEqMorphoA(depositUSDCmId, 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, 46216366450, 110999999999999999712);

        assertEq(rebalanceAdapter.sqrtPriceLastRebalance(), initialSQRTPrice);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance();

        assertEq(rebalanceAdapter.sqrtPriceLastRebalance(), 1199991337229301579466306546906758);

        assertEqBalanceState(address(hook), 0, 0);
        assertEqMorphoA(depositUSDCmId, 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, 0, 0, 98956727267096030628);
    }

    function test_swap_price_down_rebalance_withdraw() public {
        test_swap_price_down_rebalance();

        uint256 shares = hook.balanceOf(alice.addr);
        assertEqBalanceStateZero(alice.addr);
        assertApproxEqAbs(shares, 100 ether, 1e10);

        vm.prank(alice.addr);
        hook.withdraw(alice.addr, shares / 2);

        assertApproxEqAbs(hook.balanceOf(alice.addr), shares / 2, 1e10);
        assertEqBalanceState(alice.addr, 49478363633548016058, 0);
    }

    function test_swap_price_down_withdraw() public {
        test_swap_price_down_in();

        uint256 shares = hook.balanceOf(alice.addr);
        assertEqBalanceStateZero(alice.addr);
        assertApproxEqAbs(shares, 100 ether, 1e10);

        vm.prank(alice.addr);
        hook.withdraw(alice.addr, shares / 10);

        // assertApproxEqAbs(hook.balanceOf(alice.addr), shares / 2, 1e10);
        // assertEqBalanceState(alice.addr, 49478363633548016058, 0);
    }

    function test_swap_price_up_withdraw() public {
        test_swap_price_up_in();

        uint256 shares = hook.balanceOf(alice.addr);
        assertEqBalanceStateZero(alice.addr);
        assertApproxEqAbs(shares, 100 ether, 1e10);

        vm.prank(alice.addr);
        hook.withdraw(alice.addr, shares / 2);

        assertApproxEqAbs(hook.balanceOf(alice.addr), shares / 2, 1e10);
        assertEqBalanceState(alice.addr, 49525627778055050818, 2243500000);
    }

    function test_lending_adapter_migration() public {
        test_swap_price_down_rebalance();
        // This is better to do after rebalance

        vm.startPrank(deployer.addr);
        ILendingAdapter newAdapter = new MorphoLendingAdapter();
        newAdapter.setDepositUSDCmId(depositUSDCmId);
        newAdapter.setBorrowUSDCmId(borrowUSDCmId);
        newAdapter.addAuthorizedCaller(address(hook));
        newAdapter.addAuthorizedCaller(address(rebalanceAdapter));

        // @Notice: Alice here acts as a migration contract the purpose of with is to transfer collateral between adapters
        newAdapter.addAuthorizedCaller(alice.addr);

        rebalanceAdapter.setLendingAdapter(address(newAdapter));
        hook.setLendingAdapter(address(newAdapter));

        lendingAdapter.addAuthorizedCaller(address(alice.addr));
        vm.stopPrank();

        uint256 collateral = lendingAdapter.getCollateral();
        vm.startPrank(alice.addr);
        lendingAdapter.removeCollateral(collateral);

        WETH.approve(address(newAdapter), type(uint256).max);
        newAdapter.addCollateral(collateral);
        vm.stopPrank();

        assertEqBalanceState(address(hook), 0, 0);
        assertEqMorphoA(depositUSDCmId, address(newAdapter), 0, 0, 0);
        assertEqMorphoA(borrowUSDCmId, address(newAdapter), 0, 0, 98956727267096030628);
    }

    function test_accessability() public {
        vm.expectRevert(SafeCallback.NotPoolManager.selector);
        hook.afterInitialize(address(0), key, 0, 0, "");

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
        hook.withdraw(deployer.addr, 0);

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
