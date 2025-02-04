// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// ** v4 imports
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {AaveLendingAdapter} from "@src/core/lendingAdapters/AaveLendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

contract ETHALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL); // 3843 usdc for eth (but in reversed tokens order)

        deployFreshManagerAndRouters();

        create_accounts_and_tokens();
        init_hook(address(USDC), address(WETH), 6, 18);

        // Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setIsInvertAssets(false);
            hook.setSwapPriceThreshold(1e18);
            positionManager.setFees(0);
            rebalanceAdapter.setIsInvertAssets(false);
            positionManager.setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalancePriceThreshold(1e15);
            rebalanceAdapter.setRebalanceTimeThreshold(2000);
            rebalanceAdapter.setWeight(6 * 1e17); // 0.6 (60%)
            rebalanceAdapter.setLongLeverage(3 * 1e18); // 3
            rebalanceAdapter.setShortLeverage(2 * 1e18); // 2
            rebalanceAdapter.setMaxDeviationLong(1e17); // 0.1 (1%)
            rebalanceAdapter.setMaxDeviationShort(1e17); // 0.1 (1%)
            rebalanceAdapter.setOraclePriceAtLastRebalance(3849e18);
            vm.stopPrank();
        }

        approve_accounts();
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

    uint256 slippage = 1e15;

    function test_deposit_rebalance() public {
        test_deposit();

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);

        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(180 * 1e18, 307920000000, 462146886298, 4004e16);
        assertApproxEqAbs(hook.TVL(), 99890660873473629515, 1e1);
    }

    function test_deposit_rebalance_revert_no_rebalance_needed() public {
        test_deposit_rebalance();

        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
    }

    function test_deposit_rebalance_withdraw() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());
        part_withdraw();
    }

    // @Notice: this is needed for composability testing
    function part_withdraw() public {
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0);
        assertEq(hook.balanceOf(alice.addr), 0);

        assertEqBalanceState(alice.addr, 99671469151079068801, 0);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(hook.TVL(), 0, 1e4);
        assertEqBalanceStateZero(address(hook));
    }

    function test_deposit_rebalance_withdraw_on_shutdown() public {
        test_deposit_rebalance();

        vm.prank(deployer.addr);
        hook.setShutdown(true);

        part_withdraw();
    }

    function test_deposit_rebalance_withdraw_revert_min_out() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.expectRevert(IALM.NotMinOutWithdraw.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, type(uint256).max);
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        test_deposit_rebalance();
        part_swap_price_up_in();
    }

    // @Notice: this is needed for composability testing
    function part_swap_price_up_in() public {
        uint256 usdcToSwap = 17897776432;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 4626805947735540197, 1e4);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173406801524476855220, 307920000000, 444249109866, 38073607472212395416);

        assertEq(hook.sqrtPriceCurrent(), 1270692167884249415165740426235478);
        assertApproxEqAbs(hook.TVL(), 99913835812202105946, 1e1);
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 4626903915919660000;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 17898157290);
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 4626903915919660000, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173406661919814484500, 307920000000, 444248729008, 38073565835734144500);

        assertEq(hook.sqrtPriceCurrent(), 1270692033691648863352713011702213);
        assertApproxEqAbs(hook.TVL(), 99913836793875091884, 1e1);
    }

    function test_deposit_rebalance_swap_price_up_out_revert_deviations() public {
        test_deposit_rebalance();

        vm.prank(deployer.addr);
        hook.setSwapPriceThreshold(3 * 1e15);

        uint256 wethToGetFSwap = 4626903915919660000;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        vm.expectRevert();
        swapUSDC_WETH_Out(wethToGetFSwap);
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        uint256 wethToSwap = 4696832668752530000;
        test_deposit_rebalance();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 17987871838);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186692986552972355250, 307920000000, 480134758137, 42036153884219825249);

        assertEq(hook.sqrtPriceCurrent(), 1283463286628492184493879892596945);
        assertApproxEqAbs(hook.TVL(), 99914105171480511295, 1e1);
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        uint256 usdcToGetFSwap = 17987491283;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 4696732800805156176);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186692844241147347549, 307920000000, 480134377581, 42036111440342191374);

        assertEq(hook.sqrtPriceCurrent(), 1283463149833677722315484726714060);
        assertApproxEqAbs(hook.TVL(), 99914104174928305045, 1e1);
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        uint256 usdcToSwap = 17897776432;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 4624504019982289378, 1e4);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173410081771525237636, 307920000000, 444249109866, 38074585791507527014);

        assertEq(hook.sqrtPriceCurrent(), 1270695320965775488682522591655933);
        assertApproxEqAbs(hook.TVL(), 99916137739955356764, 1e1);
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        uint256 wethToGetFSwap = 4626903915919660000;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 17907106368);
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 4626903915919660000, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173406661919814484500, 307920000000, 444239779931, 38073565835734144500);

        assertEq(hook.sqrtPriceCurrent(), 1270692033691648863352713011702213);
        assertApproxEqAbs(hook.TVL(), 99916161833365868709, 1e1);
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        uint256 wethToSwap = 4696832668752530000;
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 17978922963);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186692986552972355250, 307920000000, 480125809262, 42036153884219825249);

        assertEq(hook.sqrtPriceCurrent(), 1283460069868909267964367933948804);
        assertApproxEqAbs(hook.TVL(), 99916430158490124182, 1e1);
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        uint256 usdcToGetFSwap = 17987491283;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 4699081167205558754);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186696190663267921224, 307920000000, 480134377581, 42037109496062362469);

        assertEq(hook.sqrtPriceCurrent(), 1283463149833677722315484726714060);
        assertApproxEqAbs(hook.TVL(), 99916452541328707625, 1e1);
    }

    function test_deposit_rebalance_swap_rebalance() public {
        test_deposit_rebalance_swap_price_up_in();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        rebalanceAdapter.rebalance(slippage);

        // ** Second rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);

            assertEqBalanceStateZero(address(hook));
            assertEqPositionState(180477474306962171598, 311830756139, 467412423459, 40146211506948696394);
            assertApproxEqAbs(hook.TVL(), 100310997799059398554, 1e1);
        }
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        // positionManager.setFees(5 * 1e16);
        rebalanceAdapter.setRebalancePriceThreshold(1e15);
        rebalanceAdapter.setRebalanceTimeThreshold(60 * 60 * 24 * 7);

        vm.stopPrank();
        test_deposit_rebalance();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Swap Up In
        {
            uint256 usdcToSwap = 17897776432;
            deal(address(USDC), address(swapper.addr), usdcToSwap);
            swapUSDC_WETH_In(usdcToSwap);
        }

        // ** Swap Down Out
        {
            uint256 usdcToGetFSwap = 17987491283 * 5;
            (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
            deal(address(WETH), address(swapper.addr), wethToSwapQ);
            swapWETH_USDC_Out(usdcToGetFSwap);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 2, 0);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Deposit
        //{
        //    uint256 _amountToDep = 20 ether;
        //    deal(address(WETH), address(alice.addr), _amountToDep);
        //    vm.prank(alice.addr);
        //    hook.deposit(alice.addr, _amountToDep);
        //}

        // ** Swap Up out
        {
            uint256 wethToGetFSwap = 4626903915919660000;
            (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);
            swapUSDC_WETH_Out(wethToGetFSwap);
        }

        // ** Swap Down In
        {
            uint256 wethToSwap = 4696832668752530000;
            deal(address(WETH), address(swapper.addr), wethToSwap);
            swapWETH_USDC_In(wethToSwap);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // // ** Rebalance
        // vm.prank(deployer.addr);
        // rebalanceAdapter.rebalance(1e15);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // // ** Full withdraw
        // {
        //     uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        //     vm.prank(alice.addr);
        //     hook.withdraw(alice.addr, sharesToWithdraw, 0);
        // }
    }

    function test_lending_adapter_migration() public {
        test_deposit_rebalance();

        uint256 CLbefore = lendingAdapter.getCollateralLong();
        uint256 CSbefore = lendingAdapter.getCollateralShort();
        uint256 DLbefore = lendingAdapter.getBorrowedLong();
        uint256 DSbefore = lendingAdapter.getBorrowedShort();

        // ** Create new lending adapter
        ILendingAdapter newAdapter;
        {
            vm.startPrank(deployer.addr);
            newAdapter = new AaveLendingAdapter();
            IBase(address(newAdapter)).setTokens(address(USDC), address(WETH), 6, 18);
            IBase(address(newAdapter)).setComponents(
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                migrationContract.addr,
                address(swapAdapter)
            );
        }

        // ** Withdraw collateral
        {
            IBase(address(lendingAdapter)).setComponents(
                address(hook),
                migrationContract.addr,
                migrationContract.addr,
                migrationContract.addr,
                migrationContract.addr,
                migrationContract.addr
            );
            vm.stopPrank();

            // @Notice: This is like zero interest FL
            deal(address(USDC), migrationContract.addr, DLbefore);
            deal(address(WETH), migrationContract.addr, DSbefore);

            vm.startPrank(migrationContract.addr);
            USDC.approve(address(lendingAdapter), type(uint256).max);
            WETH.approve(address(lendingAdapter), type(uint256).max);

            lendingAdapter.repayLong(DLbefore);
            lendingAdapter.repayShort(DSbefore);

            lendingAdapter.removeCollateralLong(CLbefore);
            lendingAdapter.removeCollateralShort(CSbefore);
        }

        // ** Create the same position in the new lending adapter
        {
            USDC.approve(address(newAdapter), type(uint256).max);
            WETH.approve(address(newAdapter), type(uint256).max);

            newAdapter.addCollateralLong(CLbefore);
            newAdapter.addCollateralShort(CSbefore);
            newAdapter.borrowLong(DLbefore);
            newAdapter.borrowShort(DSbefore);

            // @Notice: Here we repay our FL
            USDC.transfer(zero.addr, DLbefore);
            WETH.transfer(zero.addr, DSbefore);
            vm.stopPrank();
        }

        // ** Connect all parts properly
        {
            vm.startPrank(deployer.addr);

            hook.setComponents(
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                address(rebalanceAdapter),
                address(swapAdapter)
            );

            IBase(address(newAdapter)).setComponents(
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                address(rebalanceAdapter),
                address(swapAdapter)
            );

            IBase(address(positionManager)).setComponents(
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                address(rebalanceAdapter),
                address(swapAdapter)
            );

            IBase(address(rebalanceAdapter)).setComponents(
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                address(rebalanceAdapter),
                address(swapAdapter)
            );
            vm.stopPrank();
        }

        assertEqBalanceStateZero(migrationContract.addr);

        // ** Check if states are the same
        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(180 * 1e18, 307920000000, 462146886298, 4004e16);
        assertApproxEqAbs(hook.TVL(), 99890660873473629515, 1e1);

        // ** Check if the same test case works for the new lending adapter
        part_swap_price_up_in();
    }
}
