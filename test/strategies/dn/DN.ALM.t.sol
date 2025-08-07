// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

// ** contracts
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeltaNeutral_ALMTest is ALMTestBase {
    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 3e18;
    uint256 weight = 45e16;
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 2e15;
    uint24 feeLP = 500; //0.05%

    uint256 k1 = 1425e15; //1.425
    uint256 k2 = 1425e15; //1.425

    IERC20 WETH = IERC20(MConstants.WETH);
    IERC20 USDC = IERC20(MConstants.USDC);

    function setUp() public {
        select_mainnet_fork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = MConstants.uniswap_v3_USDC_WETH_POOL;
            ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_euler_USDC_WETH();
        create_flash_loan_adapter_euler_USDC_WETH();
        create_oracle(MConstants.chainlink_feed_USDC, MConstants.chainlink_feed_WETH, true);
        init_hook(true, false, liquidityMultiplier, 0, 1000000 ether, 3000, 3000, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            // hook.setNextLPFee(0); // By default, dynamic-fee-pools initialize with a 0% fee, to change - call rebalance.
            positionManager.setKParams(k1, k2);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(TestLib.ONE_PERCENT_AND_ONE_BPS, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();
    }

    function test_setUp() public view {
        assertEq(hook.owner(), deployer.addr);
        assertTicks(194466, 200466);
    }

    function test_withdraw() public {
        vm.expectRevert(IALM.NotZeroShares.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 0, 0, 0);

        vm.expectRevert();
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 10, 0, 0);
    }

    uint256 amountToDep = 100 * 2660 * 1e6;

    function test_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(USDC), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);
        assertApproxEqAbs(shares, amountToDep, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(0, amountToDep, 0, 0);

        assertEqProtocolState(initialSQRTPrice, amountToDep);
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        test_deposit();

        // uint256 preRebalanceTVL = calcTVL();

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        // assertEqBalanceStateZero(address(hook));
        // _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        assertTicks(194458, 200458);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1536110044317873455854701961688542, 1e1, "sqrtPrice");
    }

    function test_deposit_rebalance_revert_no_rebalance_needed() public {
        test_deposit_rebalance();

        vm.expectRevert(SRebalanceAdapter.RebalanceConditionNotMet.selector);
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
    }

    function test_deposit_rebalance_withdraw() public {
        test_deposit_rebalance();
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        assertEq(hook.balanceOf(alice.addr), 0);

        assertEqBalanceState(alice.addr, 0, 265963112062);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(calcTVL(), 0, 1e4, "tvl");
        assertEqBalanceStateZero(address(hook));
    }

    function test_deposit_rebalance_withdraw_revert_min_out() public {
        test_deposit_rebalance();
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.expectRevert(IALM.NotMinOutWithdrawBase.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, type(uint256).max, 0);
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 14171775946;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5295866784071586680, 1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127443171714058210075, 438899999998, 224634367794, 107960914090740859882);
        assertEqProtocolState(1527037186087795752853430779674447, 266092360230);
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 wethToGetFSwap = 5295866784427776090;
        uint256 usdcToSwapQ = quoteUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(usdcToSwapQ, 14171775947, 1);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, wethToGetFSwap, 1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127443171713550640167, 438899999998, 224634367797, 107960914090589479383);
        assertEqProtocolState(1527037186087185530551846525013708, 266092360229);
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 wethToSwap = 5436304955762950000;
        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14374512916);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516443322424843, 438899999998, 253180656652, 112522087080170537970);
        assertEqProtocolState(1545423500673583661086896857941818, 266095809126);
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14374512916;
        uint256 wethToSwapQ = quoteWETH_USDC_Out(usdcToGetFSwap);
        assertEq(wethToSwapQ, 5436304955754881212);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516443310926820, 438899999998, 253180656656, 112522087080167108735);
        assertEqProtocolState(1545423500673569837670446692910291, 266095809125); //rounding error for sqrt price 1e18????
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 14171775946;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5293234482239788562, 1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127446922744168522392, 438899999998, 224634367795, 107962032819019374082);
        assertEqProtocolState(1527041695736983022767290871193298, 266099362682);
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 wethToGetFSwap = 5295866784427776090;
        uint256 usdcToSwapQ = quoteUSDC_WETH_Out(wethToGetFSwap);
        assertEq(usdcToSwapQ, 14178865381);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5295866784427776090, 1e1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127443171713550640167, 438899999998, 224627278364, 107960914090589479383);
        assertEqProtocolState(1527037186087185530551846525013708, 266099449662);
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);

        // ** Before swap State
        uint256 wethToSwap = 5436304955762950000;
        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14374512916);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516443322424843, 438899999998, 253180656652, 112522087080170537970);
        assertEqProtocolState(1545423500673583661086896857941818, 266095809126);
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14374512916;
        uint256 wethToSwapQ = quoteWETH_USDC_Out(usdcToGetFSwap);
        assertEq(wethToSwapQ, 5439024467988875650);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142740391748244368893, 438899999998, 253180656656, 112523242872866556371);
        assertEqProtocolState(1545423500673569837670446692910291, 266103043575); //rounding error for sqrt price 1e18????
    }

    function test_deposit_rebalance_swap_rebalance() public {
        test_deposit_rebalance_swap_price_up_in();

        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.RebalanceConditionNotMet.selector);
        rebalanceAdapter.rebalance(slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        // ** Second rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);

            assertEqBalanceStateZero(address(hook));
            assertEqPositionState(133755977315371030169, 440071573502, 239459617218, 109204324590619965745);
            assertApproxEqAbs(calcTVL(), 266702705321, 1, "tvl");
        }
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;

        test_deposit_rebalance();

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        uint256 treasuryFeeB;
        uint256 treasuryFeeQ;

        // ** Swap Up In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdcToSwap = 10e9; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);

            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                hook.sqrtPriceCurrent()
            );

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - (deltaWETH * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaWETH) / 1e18
            );
        }

        // ** Swap Up In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            assertApproxEqAbs(deltaWETH, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - (deltaWETH * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaWETH) / 1e18
            );
        }

        // ** Swap Down Out
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            console.log("CL %s", CL);
            console.log("CS %s", CS);
            console.log("DL %s", DL);
            console.log("DS %s", DS);

            uint256 usdcToGetFSwap = 10000e6; //20k USDC
            deal(address(WETH), address(swapper.addr), quoteWETH_USDC_Out(usdcToGetFSwap));

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_Out(usdcToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                hook.sqrtPriceCurrent()
            );
            assertApproxEqAbs((deltaWETH * (1e18 - testFee)) / 1e18, deltaX, 2);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaWETH * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            assertEqPositionState(
                CL + ((deltaWETH - deltaTreasuryFee) * k1) / 1e18,
                CS,
                DL + usdcToGetFSwap,
                DS + ((k1 - 1e18) * (deltaWETH - deltaTreasuryFee)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        // ** Withdraw
        {
            console.log("shares before withdraw %s", hook.totalSupply());
            console.log("tvl pre %s", hook.TVL(oracle.price()));

            console.log("CL pre %s", lendingAdapter.getCollateralLong());
            console.log("CS pre %s", lendingAdapter.getCollateralShort());
            console.log("DL pre %s", lendingAdapter.getBorrowedLong());
            console.log("DS pre %s", lendingAdapter.getBorrowedShort());

            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 2, 0, 0);

            console.log("shares after withdraw %s", hook.totalSupply());
            console.log("tvl after %s", hook.TVL(oracle.price()));

            console.log("CL after %s", lendingAdapter.getCollateralLong());
            console.log("CS after %s", lendingAdapter.getCollateralShort());
            console.log("DL after %s", lendingAdapter.getBorrowedLong());
            console.log("DS after %s", lendingAdapter.getBorrowedShort());

            _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        }

        // ** Deposit
        {
            uint256 _amountToDep = 200 * 2485 * 1e6; //200 ETH in USDC
            deal(address(USDC), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            hook.deposit(alice.addr, _amountToDep, 0);
        }

        // ** Swap Up In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdcToSwap = 10000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            assertApproxEqAbs(deltaWETH, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - (deltaWETH * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaWETH) / 1e18
            );
        }

        // ** Swap Up Out
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 wethToGetFSwap = 5e18;
            deal(address(USDC), address(swapper.addr), quoteUSDC_WETH_Out(wethToGetFSwap));

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaWETH %s", deltaWETH);

            assertApproxEqAbs(deltaWETH, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - ((deltaWETH) * k1) / 1e18,
                CS,
                DL - deltaUSDC + deltaTreasuryFee,
                DS - ((k1 - 1e18) * (deltaWETH)) / 1e18
            );
        }

        // ** Swap Down In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 wethToSwap = 10e18;
            deal(address(WETH), address(swapper.addr), wethToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_In(wethToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
            assertApproxEqAbs((deltaWETH * (1e18 - testFee)) / 1e18, deltaX, 3);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaWETH * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL + ((deltaWETH - deltaTreasuryFee) * k1) / 1e18,
                CS,
                DL + deltaUSDC,
                DS + ((k1 - 1e18) * (deltaWETH - deltaTreasuryFee)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        // ** Rebalance
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);

            _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        }
    }

    // ** Helpers

    function swapWETH_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(false, int256(amount), key);
    }

    function quoteWETH_USDC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapWETH_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(false, -int256(amount), key);
    }

    function swapUSDC_WETH_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(true, int256(amount), key);
    }

    function quoteUSDC_WETH_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function swapUSDC_WETH_In(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(true, -int256(amount), key);
    }
}
