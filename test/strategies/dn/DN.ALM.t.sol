// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {TokenWrapperLib as TW} from "@src/libraries/TokenWrapperLib.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";

contract DeltaNeutralALMTest is MorphoTestBase {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 3e18;
    uint256 weight = 45e16;
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 2e15;
    uint24 fee = 500; //0.05%

    uint256 k1 = 1425e15; //1.425
    uint256 k2 = 1425e15; //1.425

    IERC20 WETH = IERC20(TestLib.WETH);
    IERC20 USDC = IERC20(TestLib.USDC);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_WETH_USDC_POOL;
            assertEqPSThresholdCL = 1e1;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e1;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        create_flash_loan_adapter_euler_WETH_USDC();
        create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC, 1 hours, 10 hours);
        init_hook(true, true, false, 0, 1000000 ether, 3000, 3000, TestLib.sqrt_price_10per_price_change);
        assertEq(hook.tickLower(), 194466);
        assertEq(hook.tickUpper(), 200466);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            IPositionManagerStandard(address(positionManager)).setFees(0);
            IPositionManagerStandard(address(positionManager)).setKParams(k1, k2);
            rebalanceAdapter.setRebalanceParams(weight, liquidityMultiplier, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(TestLib.ONE_PERCENT_AND_ONE_BPS, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();
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
        assertEq(hook.TVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(USDC), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);
        assertApproxEqAbs(shares, amountToDep * 1e12, c6to18(1e1));
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");

        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(0, amountToDep, 0, 0);

        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(hook.TVL(), amountToDep * 1e12, c6to18(1e1), "tvl");
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        test_deposit();

        uint256 preRebalanceTVL = hook.TVL();

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        assertEqHookPositionStateDN(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
    }

    function test_deposit_rebalance_revert_no_rebalance_needed() public {
        test_deposit_rebalance();

        vm.expectRevert(SRebalanceAdapter.RebalanceConditionNotMet.selector);
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
    }

    function test_deposit_rebalance_withdraw() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        assertEq(hook.balanceOf(alice.addr), 0);

        assertEqBalanceState(alice.addr, 0, 265934116614);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(hook.TVL(), 0, 1e4, "tvl");
        assertEqBalanceStateZero(address(hook));
    }

    function test_deposit_rebalance_withdraw_revert_min_out() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.expectRevert(IALM.NotMinOutWithdrawBase.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, type(uint256).max, 0);
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        test_deposit_rebalance();
        uint256 usdcToSwap = 14171775946;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5295866784427791744, 1e4);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127443171681682916380, 438899999998, 224634367779, 107960914064403859024);

        assertEq(hook.sqrtPriceCurrent(), 1527037186085043629240765075026281);
        assertApproxEqAbs(hook.TVL(), 266092360246006656700794, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 5295866784427776090;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertApproxEqAbs(usdcToSwapQ, 14171775946, 1);
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5295866784427776090, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127443171681682938688, 438899999998, 224634367779, 107960914064403865677);

        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1527037186085043656060480983588712, 1e13); //rounding error for sqrt price
        assertApproxEqAbs(hook.TVL(), 266092360246006698346246, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        uint256 wethToSwap = 5436304955762950000;
        test_deposit_rebalance();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14374512916);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516411454723365, 438899999998, 253180656641, 112522087053984924265);

        assertEq(hook.sqrtPriceCurrent(), 1545423500675782334768365615423236);
        assertApproxEqAbs(hook.TVL(), 266095809142564975018941, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        uint256 usdcToGetFSwap = 14374512916;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5436304955762662335);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516411454313441, 438899999998, 253180656641, 112522087053984802007);

        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1545423500675782334768365615423236, 1e18); //rounding error for sqrt price
        assertApproxEqAbs(hook.TVL(), 266095809142564209769459, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(500);
        uint256 usdcToSwap = 14171775946;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5293234482967489261, 1e4);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127446922711263847418, 438899999998, 224634367779, 107962032792524487579);

        assertEq(hook.sqrtPriceCurrent(), 1527037186085043629240765075026281);
        assertApproxEqAbs(hook.TVL(), 266099362697906645615735, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(500);

        uint256 wethToGetFSwap = 5295866784427776090;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 14171775946); //more
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5295866784427776090, 1e1);

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127443171681682938688, 438899999998, 224634367779, 107960914064403865677);

        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1527037186085043656058988429916357, 1e13); //rounding error for sqrt price
        assertApproxEqAbs(hook.TVL(), 266092360246006698346246, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        uint256 wethToSwap = 5436304955762950000;
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(500);

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14367368951); //less

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516411454723365, 438899999998, 253173512676, 112522087053984924265);

        assertEq(hook.sqrtPriceCurrent(), 1545423500675782334768365615423236);
        assertApproxEqAbs(hook.TVL(), 266102953107564975018941, 1e1, "tvl"); //more
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(500);

        uint256 usdcToGetFSwap = 14374512916;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5436304955762662335); //more

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516411454313441, 438899999998, 253180656641, 112522087053984802007);

        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1545423500675782334768365615423236, 1e18); //rounding error for sqrt price
        assertApproxEqAbs(hook.TVL(), 266095809142564209769459, 1e1, "tvl"); //more
    }

    function test_deposit_rebalance_swap_rebalance() public {
        test_deposit_rebalance_swap_price_up_in();

        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.RebalanceConditionNotMet.selector);
        rebalanceAdapter.rebalance(slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Second rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);

            assertEqBalanceStateZero(address(hook));
            assertEqPositionState(133755977324812817944, 440071573498, 239292883052, 109204324598080509639);
            assertApproxEqAbs(hook.TVL(), 266869439484208695046603, 1e1, "tvl");
        }
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);

        IPositionManagerStandard(address(positionManager)).setFees(fee);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)

        IPositionManagerStandard(address(positionManager)).setFees(500);
        hook.setProtocolParams(
            20 * 1e16, // 20% from fees
            hook.tvlCap(),
            hook.tickUpperDelta(),
            hook.tickLowerDelta(),
            hook.swapPriceThreshold()
        );

        vm.stopPrank();
        test_deposit_rebalance();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

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

            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaX * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                CL - ((deltaWETH + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdcToSwap,
                DS - ((k1 - 1e18) * (deltaWETH + deltaTreasuryFee)) / 1e18
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

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaX * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                CL - ((deltaWETH + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdcToSwap,
                DS - ((k1 - 1e18) * (deltaWETH + deltaTreasuryFee)) / 1e18
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

            uint256 usdcToGetFSwap = 20000e6; //20k USDC
            (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
            deal(address(WETH), address(swapper.addr), wethToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_Out(usdcToGetFSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 + fee)) / 1e18, 1);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaX * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                CL + ((deltaWETH - deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) + usdcToGetFSwap,
                DS + ((k1 - 1e18) * (deltaWETH - deltaTreasuryFee)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 2, 0, 0);

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

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaX * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                CL - ((deltaWETH + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdcToSwap,
                DS - ((k1 - 1e18) * (deltaWETH + deltaTreasuryFee)) / 1e18
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
            (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(hook.sqrtPriceCurrent())
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 + fee)) / 1e18, 1);

            uint256 deltaTreasuryFee = (deltaY * fee * hook.protocolFee()) / 1e36;
            // treasuryFeeB += deltaTreasuryFee;
            // assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            // assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            // console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - ((deltaWETH) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdcToSwapQ + deltaTreasuryFee,
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

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_In(wethToSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 - fee)) / 1e18, 1);

            uint256 deltaTreasuryFee = (deltaY * fee * hook.protocolFee()) / 1e36;
            // treasuryFeeB += deltaTreasuryFee;
            // assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            // assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            // console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL + ((deltaWETH) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) + deltaUSDC + deltaTreasuryFee,
                DS + ((k1 - 1e18) * (deltaWETH)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Rebalance
        uint256 preRebalanceTVL = hook.TVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        //assertEqHookPositionStateDN(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

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
