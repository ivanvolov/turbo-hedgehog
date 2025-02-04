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

        initialSQRTPrice = getPoolSQRTPrice(TARGET_SWAP_POOL); // 3843 usdc for eth (but in reversed tokens order)

        deployFreshManagerAndRouters();

        create_accounts_and_tokens();
        init_hook(address(USDC), address(WETH), 6, 18);

        // Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setIsInvertAssets(true);
            hook.setSwapPriceThreshold(1e18);
            rebalanceAdapter.setIsInvertAssets(true);
            positionManager.setFees(0);
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
        assertApproxEqAbs(deltaWETH, 5323851733135280144, 1e4); //done

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127203067009042942864, 634095000000, 325455619970, 107675718430408932339); //done

        assertEq(hook.sqrtPriceCurrent(), 1270696828650359021354068986114864); //done
        assertApproxEqAbs(hook.TVL(), 383800144709162306510725, 1e1); //done
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 5331823310823070000; //done
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 20625058578); //done
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5331823310823070000, 1e1); //done

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127191707510837842319, 634095000000, 325424629883, 107672330509891621649); //done

        assertEq(hook.sqrtPriceCurrent(), 1270687346133515048399874137317894); //done
        assertApproxEqAbs(hook.TVL(), 383800452193642003358830, 1e1); //done
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        uint256 wethToSwap = 5408396534130190000;
        test_deposit_rebalance();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 20713010531); //done

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142496520789896237819, 634095000000, 366762698992, 112236923943996757149); //done

        assertEq(hook.sqrtPriceCurrent(), 1283463275764576390572897434700206); //done
        assertApproxEqAbs(hook.TVL(), 383801489267867101098830, 1e1); //done
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        uint256 usdcToGetFSwap = 20697298845; //done
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5404273386596029990); //done

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142490645304660059804, 634095000000, 366746987307, 112235171606294739144); //done

        assertEq(hook.sqrtPriceCurrent(), 1283458371112389064549618491520823);
        assertApproxEqAbs(hook.TVL(), 383801330958008119220340, 1e1);
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);
        uint256 usdcToSwap = 20594068491; //done

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5321203001563470507, 1e4); //done

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127206841451532771596, 634095000000, 325455619970, 107676844141326951434); //done

        assertEq(hook.sqrtPriceCurrent(), 1270699979424613322261916498096605); //done
        assertApproxEqAbs(hook.TVL(), 383810339676982201803538, 1e1); //done
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        uint256 wethToGetFSwap = 5331823310823070000; //done
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 20635371107); //done
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5331823310823070000, 1e1); //done

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127191707510837842319, 634095000000, 325414317354, 107672330509891621649); //done

        assertEq(hook.sqrtPriceCurrent(), 1270687346133515048399874137317894); //done
        assertApproxEqAbs(hook.TVL(), 383810764722642003358830, 1e1); //done
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        uint256 wethToSwap = 5408396534130190000;
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 20702705913); //done

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142496520789896237819, 634095000000, 366752394374, 112236923943996757149); //done

        assertEq(hook.sqrtPriceCurrent(), 1283460059010425431940345967281013); //done
        assertApproxEqAbs(hook.TVL(), 383811793885867101098830, 1e1); //done
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        uint256 usdcToGetFSwap = 20697298845; //done
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5406975523289328004); //done

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142494495849448009474, 634095000000, 366746987307, 112236320014389390800); //done

        assertEq(hook.sqrtPriceCurrent(), 1283458371112389064549618491520823);
        assertApproxEqAbs(hook.TVL(), 383811731482140623276226, 1e1);
    }

    function test_deposit_rebalance_swap_rebalance() public {
        // console.log("price (1)", getHookPrice());
        test_deposit_rebalance_swap_price_up_in();
        // console.log("price (2)", getHookPrice());

        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        rebalanceAdapter.rebalance(slippage);

        // ** Make oracle change with swap price
        vm.mockCall(address(hook.oracle()), abi.encodeWithSelector(IOracle.price.selector), abi.encode(getHookPrice()));

        // ** Second rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);

            assertEqBalanceStateZero(address(hook));
            assertEqPositionState(133540952742063250489, 634512119140, 345484761720, 108919957825396922361);
            assertApproxEqAbs(hook.TVL(), 384742549210321332953535, 1e1);
        }
    }
}
