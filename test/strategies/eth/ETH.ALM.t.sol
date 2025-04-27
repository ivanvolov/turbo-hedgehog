// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";

// ** contracts
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";

contract ETHALMTest is MorphoTestBase {
    using SafeERC20 for IERC20;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 50e16; //50%
    uint256 slippage = 15e14; //0.15%
    uint256 fee = 5e14; //0.05%

    IERC20 WETH = IERC20(TestLib.WETH);
    IERC20 USDC = IERC20(TestLib.USDC);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(TestLib.startBlock);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_WETH_USDC_POOL;
            
            //account for rounding errors for exact inputs and exact outputs
            assertEqPSThresholdCL = 1e12; 
            assertEqPSThresholdCS = 1e6;
            assertEqPSThresholdDL = 1e6;
            assertEqPSThresholdDS = 1e12;
            assertEqSqrtThreshold = 1e21;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        // create_lending_adapter_morpho();
        create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC);
        init_hook(true, false, 3000, 3000);
        assertEq(hook.tickLower(), 204369);
        assertEq(hook.tickUpper(), 198369);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setIsInvertAssets(false);
            hook.setTVLCap(1000 ether);
            hook.setSwapPriceThreshold(TestLib.sqrt_price_10per_price_change);
            rebalanceAdapter.setIsInvertAssets(false);
            IPositionManagerStandard(address(positionManager)).setFees(0);
            IPositionManagerStandard(address(positionManager)).setKParams(1.425e18, 1.425e18); // 1.425 1.425
            rebalanceAdapter.setRebalancePriceThreshold(1e15);
            rebalanceAdapter.setRebalanceTimeThreshold(2000);
            rebalanceAdapter.setWeight(weight);
            rebalanceAdapter.setLongLeverage(longLeverage);
            rebalanceAdapter.setShortLeverage(shortLeverage);
            rebalanceAdapter.setMaxDeviationLong(1e17); // 0.1 (1%)
            rebalanceAdapter.setMaxDeviationShort(1e17); // 0.1 (1%)
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

        assertApproxEqAbs(shares, amountToDep, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(hook.TVL(), amountToDep, 1e1, "tvl");
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_cap() public {
        vm.prank(deployer.addr);
        hook.setTVLCap(10 ether);

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        vm.expectRevert(IALM.TVLCapExceeded.selector);
        hook.deposit(alice.addr, amountToDep);
    }

    function test_deposit_not_operator() public {
        vm.prank(deployer.addr);
        hook.setLiquidityOperator(deployer.addr);
        deal(address(WETH), address(alice.addr), amountToDep);

        vm.prank(alice.addr);
        vm.expectRevert(IALM.NotALiquidityOperator.selector);
        hook.deposit(alice.addr, amountToDep);

        vm.prank(deployer.addr);
        hook.setLiquidityOperator(alice.addr);

        vm.prank(alice.addr);
        hook.deposit(alice.addr, amountToDep);
    }

    function test_deposit_rebalance() public {
        test_deposit();

        uint256 preRebalanceTVL = hook.TVL();

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
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

    function test_deposit_rebalance_withdraw_not_operator() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        vm.prank(deployer.addr);
        hook.setLiquidityOperator(deployer.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        vm.expectRevert(IALM.NotALiquidityOperator.selector);
        hook.withdraw(alice.addr, sharesToWithdraw, 0);

        vm.prank(deployer.addr);
        hook.setLiquidityOperator(alice.addr);

        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0);
    }

    // @Notice: this is needed for composability testing
    function part_withdraw() public {
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0);
        assertEq(hook.balanceOf(alice.addr), 0);

        assertEqBalanceState(alice.addr, 99999999999443760900, 0);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(hook.TVL(), 0, 1e4, "tvl");
        assertEqBalanceStateZero(address(hook));
    }

    function test_deposit_rebalance_withdraw_on_shutdown() public {
        test_deposit_rebalance();

        alignOraclesAndPools(hook.sqrtPriceCurrent());

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
        uint256 usdcToSwap = 8053204141;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 4453642739243898020, 1e4, "tvl");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(143653559096577445321, 179918780679, 171865576539, 48107201835821343342);

        assertEq(hook.sqrtPriceCurrent(), 1858542917553885659636781275009823);
        assertApproxEqAbs(hook.TVL(), 100022379224408581851, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);

        uint256 usdcToSwap = 8053204141;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 4451415917874270000, 1e4);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(143656732317029156599, 179918780679, 171865576539, 48108148234903432671);

        assertEq(hook.sqrtPriceCurrent(), 1858542917553885659636781275009823);
        assertApproxEqAbs(hook.TVL(), 100024606045778203800, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 4453642739243898020;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertApproxEqAbs(usdcToSwapQ, 8053204141, 1, "deltaUSDCQuote");

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 4453642739243898020, 1, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(143653559096577445321, 179918780679, 171865576539, 48107201835821343342);

        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1858542917553885659636781275009823, assertEqSqrtThreshold, "nextSqrtPrice"); //max diff is 1e12 due to the rounding directions
        assertApproxEqAbs(hook.TVL(), 100022379223852775506, 1e1, "tvl");
    }


    function test_deposit_rebalance_swap_price_up_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);

        uint256 wethToGetFSwap = 4453642739243898020;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 8057230742);
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 4453642739243898020, 1e1, "tvl");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(143653559096577445321, 179918780679, 171861549938, 48107201835821343342);

        assertEq(hook.sqrtPriceCurrent(), 1858542917553885659637771333251586);
        assertApproxEqAbs(hook.TVL(), 100024617234795695302, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_not_operator() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 4453642739243898020;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertApproxEqAbs(usdcToSwapQ, 8053204141, 1e4, "deltaUSDCQuote");
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        vm.prank(deployer.addr);
        hook.setSwapOperator(deployer.addr);

        part_swap_USDC_WETH_OUT_revert(wethToGetFSwap);

        vm.prank(deployer.addr);
        hook.setSwapOperator(address(swapRouter));

        swapUSDC_WETH_Out(wethToGetFSwap);
    }

    function test_deposit_rebalance_swap_price_up_out_revert_deviations() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 100e18;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        part_swap_USDC_WETH_OUT_revert(wethToGetFSwap);
    }

    function part_swap_USDC_WETH_OUT_revert(uint256 amount) internal {
        bool hasReverted = false;
        try this.swapUSDC_WETH_Out(amount) {
            hasReverted = false;
        } catch {
            hasReverted = true;
            vm.stopPrank();
        }
        assertTrue(hasReverted, "Expected function to revert but it didn't");
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        uint256 wethToSwap = 4520952484861000000;
        test_deposit_rebalance();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 8093572585);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(156442357290926924999, 179918780679, 188012353265, 51921404806065925001);

        assertEq(hook.sqrtPriceCurrent(), 1877221861218958057946486020370141);
        assertApproxEqAbs(hook.TVL(), 100022493482758564839, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        uint256 wethToSwap = 4520952484861000000;
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 8089525799);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(156442357290926924999, 179918780679, 188008306479, 51921404806065925001);

        assertEq(hook.sqrtPriceCurrent(), 1877221861218958057946486020370141);
        assertApproxEqAbs(hook.TVL(), 100024742712096764797, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        uint256 usdcToGetFSwap = 8093572585;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertApproxEqAbs(wethToSwapQ, 4520952484861000000, 1e12, "rounding");

        console.log("here0 %s");

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        console.log("here1 %s");

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(156442357290926924999, 179918780679, 188012353265, 51921404806065925001);

        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1877221861218958057946486020370141, assertEqSqrtThreshold, "rounding error");
        assertApproxEqAbs(hook.TVL(), 100022493482577790008, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);

        uint256 usdcToGetFSwap = 8093572585;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertApproxEqAbs(wethToSwapQ, 4523212961103430000, 1e12, "rounding");

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(156445578469314655526, 179918780679, 188012353265, 51922365508392090246);

        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1877221861218958057946486020370141, assertEqSqrtThreshold, "rounding error");
        assertApproxEqAbs(hook.TVL(), 100024753958820130121, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_rebalance() public {
        test_deposit_rebalance_swap_price_up_in();

        // ** Fail swap without oracle update
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        rebalanceAdapter.rebalance(slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Second rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);

            assertEqBalanceStateZero(address(hook));
            assertEqPositionState(149966846741247506321, 181684542556, 181556094261, 50063932337119792527);
            assertApproxEqAbs(hook.TVL(), 99973597305011109736, 1e1, "tvl");
        }
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);

        IPositionManagerStandard(address(positionManager)).setFees(fee);
        rebalanceAdapter.setRebalancePriceThreshold(1e15);
        rebalanceAdapter.setRebalanceTimeThreshold(60 * 60 * 24 * 7);

        vm.stopPrank();
        test_deposit_rebalance();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Swap Up In
        {
            uint256 usdcToSwap = 50000e6; // 50k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1e3);
            assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1e15);
            assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        }

        // ** Swap Down Out
        {
            uint256 usdcToGetFSwap = 50000e6; //200k USDC
            (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
            deal(address(WETH), address(swapper.addr), wethToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_Out(usdcToGetFSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 + fee)) / 1e18, 9e14);
            assertApproxEqAbs(deltaUSDC, deltaY, 3e6);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 2, 0);
        }

        {
            uint256 usdcToSwap = 10000e6; // 50k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaWETH, deltaX, 1e15);
            assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Deposit
        {
            uint256 _amountToDep = 200 ether;
            deal(address(WETH), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            hook.deposit(alice.addr, _amountToDep);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 10000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1e15);
            assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        }

        // ** Swap Up out
        {
            uint256 wethToGetFSwap = 5e18;
            (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 3e14);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 + fee)) / 1e18, 1e7);
        }

        // ** Swap Down In
        {
            uint256 wethToSwap = 10e18;
            deal(address(WETH), address(swapper.addr), wethToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_In(wethToSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs((deltaWETH * (1e18 - fee)) / 1e18, deltaX, 42e13);
            assertApproxEqAbs(deltaUSDC, deltaY, 1e7);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Rebalance
        uint256 preRebalanceTVL = hook.TVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0);
        }
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
            newAdapter = new EulerLendingAdapter(
                0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9,
                0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2,
                0xcBC9B61177444A793B85442D3a953B90f6170b7D,
                0x716bF454066a84F39A2F78b5707e79a9d64f1225
            );
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
            USDC.forceApprove(address(lendingAdapter), type(uint256).max);
            WETH.forceApprove(address(lendingAdapter), type(uint256).max);

            lendingAdapter.repayLong(DLbefore);
            lendingAdapter.repayShort(DSbefore);

            lendingAdapter.removeCollateralLong(CLbefore);
            lendingAdapter.removeCollateralShort(CSbefore);
        }

        // ** Create the same position in the new lending adapter
        {
            USDC.forceApprove(address(newAdapter), type(uint256).max);
            WETH.forceApprove(address(newAdapter), type(uint256).max);

            newAdapter.addCollateralLong(CLbefore);
            newAdapter.addCollateralShort(CSbefore);
            newAdapter.borrowLong(DLbefore);
            newAdapter.borrowShort(DSbefore);

            // @Notice: Here we repay our FL
            USDC.safeTransfer(zero.addr, DLbefore);
            WETH.safeTransfer(zero.addr, DSbefore);
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
        assertEqPositionState(149999999999999999999, 179918780678, 179918780680, 50000000000000000001);
        assertApproxEqAbs(hook.TVL(), 99999999998888387307, 1e1, "tvl");

        // ** Check if the same test case works for the new lending adapter
        //part_swap_price_up_in();
    }

    // ** Helpers
    function swapWETH_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, int256(amount), key);
    }

    function swapWETH_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }

    function swapUSDC_WETH_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, int256(amount), key);
    }

    function swapUSDC_WETH_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, -int256(amount), key);
    }
}
