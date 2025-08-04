// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

// ** contracts
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";

contract DeltaNeutral_UNI_ALMTest is ALMTestBaseUnichain {
    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 3e18;
    uint256 weight = 45e16;
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 2e15;
    uint24 feeLP = 500; //0.05%

    uint256 k1 = 1425e15; //1.425
    uint256 k2 = 1425e15; //1.425

    IERC20 WETH = IERC20(UConstants.WETH);
    IERC20 USDC = IERC20(UConstants.USDC);
    PoolKey ETH_USDC_key;

    function setUp() public {
        select_unichain_fork(23302675); // If you decide to change the fork, you need to change the mock_latestRoundData() too.

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
            isNTS = 0;
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        manager = UConstants.manager;
        deployMockUniversalRouter(); // universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER; // deployMockV4Quoter();

        create_accounts_and_tokens(UConstants.USDC, 6, "USDC", UConstants.WETH, 18, "WETH");
        create_flash_loan_adapter_morpho_unichain();
        create_lending_adapter_euler_USDC_WETH_unichain();

        oracle = _create_oracle(
            UConstants.chronicle_feed_WETH,
            UConstants.chronicle_feed_USDC,
            24 hours,
            24 hours,
            false,
            int8(6 - 18)
        );
        mock_latestRoundData(address(UConstants.chronicle_feed_WETH), 3634568623200000000000);
        mock_latestRoundData(address(UConstants.chronicle_feed_USDC), 999820000000000000);

        production_init_hook(true, false, liquidityMultiplier, 0, 1000000 ether, 3000, 3000, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            // hook.setNextLPFee(0); // By default, dynamic-fee-pools initialize with a 0% fee, to change - call rebalance.
            IPositionManagerStandard(address(positionManager)).setKParams(k1, k2);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(TestLib.ONE_PERCENT_AND_ONE_BPS, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        // Re-setup swap router for native-token
        {
            vm.startPrank(deployer.addr);
            ETH_USDC_key = _getAndCheckPoolKey(
                ETH,
                USDC,
                500,
                10,
                0x3258f413c7a88cda2fa8709a589d221a80f6574f63df5a5b6774485d8acc39d9
            );
            uint8[4] memory config = [0, 1, 2, 1];
            setSwapAdapterToV4SingleSwap(ETH_USDC_key, config);
            vm.stopPrank();
        }

        approve_accounts();
    }

    function test_setUp() public {
        vm.skip(true);
        assertEq(hook.owner(), deployer.addr);
        assertTicks(194466, 200466);
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

        uint256 preRebalanceTVL = calcTVL();
        console.log("oraclePrice %s", oracle.price());

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);

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

        assertEqBalanceStateZero(address(hook));
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        assertTicks(-197336, -191336);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 4776888565746978846459145, 1e1, "sqrtPrice");
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 14171775946;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);
        assertApproxEqAbs(deltaETH, 5295866785352039698, 1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127443171712233564525, 438899999998, 224634367794, 107960914090196667349);
        assertEqProtocolState(1527037186270449685856601097245802, 266092360230);
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 ethToGetFSwap = 5295866784427776090;
        uint256 usdcToSwapQ = quoteUSDC_ETH_Out(ethToGetFSwap);
        assertApproxEqAbs(usdcToSwapQ, 14171775944, 1);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaETH) = swapUSDC_ETH_Out(ethToGetFSwap);
        assertApproxEqAbs(deltaETH, ethToGetFSwap, 1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127443171713550640167, 438899999998, 224634367797, 107960914090589479383);
        assertEqProtocolState(1527037186272033130649445691091552, 266092360229);
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 ethToSwap = 5436304955762950000;
        deal(address(swapper.addr), ethToSwap);
        assertEqBalanceState(swapper.addr, ethToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapETH_USDC_In(ethToSwap);
        assertEq(deltaUSDC, 14374512912);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516443322424843, 438899999998, 253180656652, 112522087080170537970);
        assertEqProtocolState(1545423500858431261183497752709464, 266095809126);
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14374512916;
        uint256 ethToSwapQ = quoteETH_USDC_Out(usdcToGetFSwap);
        assertEq(ethToSwapQ, 5436304957067201580);

        deal(address(swapper.addr), ethToSwapQ);
        assertEqBalanceState(swapper.addr, ethToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516445180983343, 438899999998, 253180656656, 112522087080724844891);
        assertEqProtocolState(1545423500860665699880725593300786, 266095809125); //rounding error for sqrt price 1e18????
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 14171775946;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);
        assertApproxEqAbs(deltaETH, 5293234483519611863, 1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127446922742344774189, 438899999998, 224634367795, 107962032818475449179);
        assertEqProtocolState(1527041695919638034599954480680065, 266099362682);
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 ethToGetFSwap = 5295866784427776090;
        uint256 usdcToSwapQ = quoteUSDC_ETH_Out(ethToGetFSwap);
        assertEq(usdcToSwapQ, 14178865378);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaETH) = swapUSDC_ETH_Out(ethToGetFSwap);
        assertApproxEqAbs(deltaETH, 5295866784427776090, 1e1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(127443171713550640167, 438899999998, 224627278364, 107960914090589479383);
        assertEqProtocolState(1527037186272033130649445691091552, 266099449662);
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        vm.skip(true);
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);

        // ** Before swap State
        uint256 ethToSwap = 5436304955762950000;
        deal(address(swapper.addr), ethToSwap);
        assertEqBalanceState(swapper.addr, ethToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapETH_USDC_In(ethToSwap);
        assertEq(deltaUSDC, 14374512912);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142736516443322424843, 438899999998, 253180656652, 112522087080170537970);
        assertEqProtocolState(1545423500858431261183497752709464, 266095809126);
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14374512916;
        uint256 ethToSwapQ = quoteETH_USDC_Out(usdcToGetFSwap);
        assertEq(ethToSwapQ, 5439024469301852507);

        deal(address(swapper.addr), ethToSwapQ);
        assertEqBalanceState(swapper.addr, ethToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(142740391750115360913, 438899999998, 253180656656, 112523242873424571535);
        assertEqProtocolState(1545423500860665699880725593300786, 266103043575); //rounding error for sqrt price 1e18????
    }

    function test_deposit_rebalance_swap_rebalance() public {
        vm.skip(true);
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
            assertEqPositionState(133755977353914710809, 440071573466, 239459617199, 109204324622254173858);
            assertApproxEqAbs(calcTVL(), 266702705299, 1, "tvl");
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
        alignOraclesAndPoolsV4(hook, ETH_USDC_key);

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

            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                hook.sqrtPriceCurrent()
            );

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaETH %s", deltaETH);

            assertApproxEqAbs(deltaETH, deltaY, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 2);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - (deltaETH * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaETH) / 1e18
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
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaETH %s", deltaETH);

            assertApproxEqAbs(deltaETH, deltaY, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 1);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - (deltaETH * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaETH) / 1e18
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
            deal(address(swapper.addr), quoteETH_USDC_Out(usdcToGetFSwap));

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapETH_USDC_Out(usdcToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                hook.sqrtPriceCurrent()
            );

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaETH %s", deltaETH);

            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 1);
            assertApproxEqAbs(deltaUSDC, deltaX, 1);

            uint256 deltaTreasuryFee = (deltaETH * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            assertEqPositionState(
                CL + ((deltaETH - deltaTreasuryFee) * k1) / 1e18,
                CS,
                DL + usdcToGetFSwap,
                DS + ((k1 - 1e18) * (deltaETH - deltaTreasuryFee)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key);

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
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaETH %s", deltaETH);

            assertApproxEqAbs(deltaETH, deltaY, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 2);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - (deltaETH * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaETH) / 1e18
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

            uint256 ethToGetFSwap = 5e18;
            deal(address(USDC), address(swapper.addr), quoteUSDC_ETH_Out(ethToGetFSwap));

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_Out(ethToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaETH %s", deltaETH);

            assertApproxEqAbs(deltaETH, deltaY, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 2);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFeeB");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - ((deltaETH) * k1) / 1e18,
                CS,
                DL - deltaUSDC + deltaTreasuryFee,
                DS - ((k1 - 1e18) * (deltaETH)) / 1e18
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

            uint256 ethToSwap = 10e18;
            deal(address(swapper.addr), ethToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapETH_USDC_In(ethToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 3);
            assertApproxEqAbs(deltaUSDC, deltaX, 1);

            uint256 deltaTreasuryFee = (deltaETH * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFeeQ");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL + ((deltaETH - deltaTreasuryFee) * k1) / 1e18,
                CS,
                DL + deltaUSDC,
                DS + ((k1 - 1e18) * (deltaETH - deltaTreasuryFee)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key);

        // ** Rebalance
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        // _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key);

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);

            // _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        }
    }

    // ** Helpers

    function swapETH_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, false, amount);
    }

    function quoteETH_USDC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function swapETH_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, true, amount);
    }

    function swapUSDC_ETH_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, false, amount);
    }

    function quoteUSDC_ETH_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapUSDC_ETH_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, true, amount);
    }

    function swapAndReturnDeltas(bool zeroForOne, bool isExactInput, uint256 amount) public returns (uint256, uint256) {
        console.log("START: swapAndReturnDeltas");
        int256 usdcBefore = int256(USDC.balanceOf(swapper.addr));
        int256 ethBefore = int256(swapper.addr.balance);

        vm.startPrank(swapper.addr);
        _swap_v4_single_throw_router(zeroForOne, isExactInput, amount, key);
        vm.stopPrank();

        int256 usdcAfter = int256(USDC.balanceOf(swapper.addr));
        int256 ethAfter = int256(swapper.addr.balance);
        console.log("END: swapAndReturnDeltas");
        return (abs(usdcAfter - usdcBefore), abs(ethAfter - ethBefore));
    }
}
