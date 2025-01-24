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
import {IOracle} from "@src/interfaces/IOracle.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

contract DeltaNeutralALMTest is ALMTestBase {
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
        init_hook(address(USDC), address(WETH), 6, 18);

        // Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setIsInvertAssets(true);
            rebalanceAdapter.setIsInvertAssets(true);
            positionManager.setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalancePriceThreshold(1e15); //10% price change
            rebalanceAdapter.setRebalanceTimeThreshold(2000);
            rebalanceAdapter.setWeight(45 * 1e16); // 0.45 (45%)
            rebalanceAdapter.setLongLeverage(3 * 1e18); // 3
            rebalanceAdapter.setShortLeverage(3 * 1e18); // 3
            rebalanceAdapter.setMaxDeviationLong(1e17); // 0.01 (1%)
            rebalanceAdapter.setMaxDeviationShort(1e17); // 0.01 (1%)
            rebalanceAdapter.setOraclePriceAtLastRebalance(1e18);
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

    uint256 amountToDep = 100 * 3843 * 1e6;

    function test_deposit() public {
        assertEq(hook.TVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(USDC), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        (, uint256 shares) = hook.deposit(alice.addr, amountToDep);
        assertEq(shares, amountToDep * 1e12, "shares returned");
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(0, amountToDep, 0, 0);

        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertEq(hook.TVL(), amountToDep * 1e12, "TVL");
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
        assertEqPositionState(134789555728760717069, 634095000000, 346049688461, 109938355416991426399);
        assertApproxEqAbs(hook.TVL(), 383697581538999999788830, 1e1);
    }

    function test_deposit_rebalance_revert_no_rebalance_needed() public {
        test_deposit_rebalance();

        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
    }

    function test_deposit_rebalance_withdraw() public {
        test_deposit_rebalance();
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0);
        assertEq(hook.balanceOf(alice.addr), 0);

        assertEqBalanceState(alice.addr, 0, 382821699797);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(hook.TVL(), 0, 1e4);
        assertEqBalanceStateZero(address(hook));
    }

    function test_deposit_rebalance_withdraw_revert_min_out() public {
        test_deposit_rebalance();
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.expectRevert(IALM.NotMinOutWithdraw.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, type(uint256).max);
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        test_deposit_rebalance();
        uint256 usdcToSwap = 20594068491; //done

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5331823310591406484, 1e4); //done

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127191707511167962830, 634095000000, 325455619970, 107672330509990078644); //done

        assertEq(hook.sqrtPriceCurrent(), 1271645440502551212531930542137883); //done
        assertApproxEqAbs(hook.TVL(), 383769462107533676231914, 1e1); //done
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 5331823310823070000; //done
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 20594068491); //done
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5331823310823070000, 1e1); //done

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127191707510837842319, 634095000000, 325455619970, 107672330509891621649); //done

        assertEq(hook.sqrtPriceCurrent(), 1271645440502275639794774138805276); //done
        assertApproxEqAbs(hook.TVL(), 383769462106642003358830, 1e1); //done
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        uint256 wethToSwap = 5412405869100890000;
        test_deposit_rebalance();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 20697298845); //done

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142502234092229485318, 634095000000, 366746987307, 112238627911359304649); //done

        assertEq(hook.sqrtPriceCurrent(), 1284426117818802190383210484719251); //done
        assertApproxEqAbs(hook.TVL(), 383832632883169325394981, 1e1); //done
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        uint256 usdcToGetFSwap = 20697298845; //done
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5412405868873678049); //done

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142502234091905708288, 634095000000, 366746987307, 112238627911262739570); //done

        assertEq(hook.sqrtPriceCurrent(), 1284426117818531912956160486717224);
        assertApproxEqAbs(hook.TVL(), 383832632882294786595582, 1e1);
    }

    function test_deposit_rebalance_swap_rebalance() public {
        // console.log("price (1)", getHookPrice());
        test_deposit_rebalance_swap_price_up_in();
        // console.log("price (2)", getHookPrice());

        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        rebalanceAdapter.rebalance(slippage);

        // ** Make oracle change with swap price
        {
            vm.mockCall(
                address(hook.oracle()),
                abi.encodeWithSelector(IOracle.price.selector),
                abi.encode(getHookPrice())
            );
            // TODO: maybe update aave lending pool here
        }

        // ** Second rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);

            assertEqBalanceStateZero(address(hook));
            assertEqPositionState(133690275324877496198, 634274255207, 345383781290, 109041749748313045287); // done
            assertApproxEqAbs(hook.TVL(), 384569784293471999376026, 1e1); //done
        }
    }

    // ** Utils

    function getHookPrice() public view returns (uint256) {
        return ALMMathLib.reversePrice(ALMMathLib.getPriceFromSqrtPriceX96(hook.sqrtPriceCurrent()));
    }
}
