// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as BConstants} from "@test/libraries/constants/BaseConstants.sol";

// ** contracts
import {ALMTestBaseBase} from "@test/core/ALMTestBaseBase.sol";

contract DeltaNeutral_R_BASE_ALMTest is ALMTestBaseBase {
    uint256 longLeverage = 2e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 40e16;
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 5e15;
    uint24 feeLP = 500; //0.05%

    uint256 k1 = 1425e15; //1.425
    uint256 k2 = 1425e15; //1.425

    IERC20 BTC = IERC20(BConstants.CBBTC);
    IERC20 USDC = IERC20(BConstants.USDC);
    PoolKey USDC_CBBTC_key;

    function setUp() public {
        select_base_fork(33774814);

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
            isNTS = 2;
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        manager = BConstants.manager;
        deployMockUniversalRouter(); // universalRouter = BConstants.UNIVERSAL_ROUTER;
        quoter = BConstants.V4_QUOTER; // deployMockV4Quoter();

        create_accounts_and_tokens(BConstants.USDC, 6, "USDC", BConstants.CBBTC, 8, "CBBTC");
        create_flash_loan_adapter_morpho_base();
        create_lending_adapter_euler_USDC_BTC_base();

        oracle = _create_oracle(
            BConstants.chainlink_feed_CBBTC,
            BConstants.chainlink_feed_USDC,
            24 hours,
            24 hours,
            true,
            int8(6 - 8)
        );
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

        // Re-setup swap router for native-token
        {
            vm.startPrank(deployer.addr);
            USDC_CBBTC_key = _getAndCheckPoolKey(
                USDC,
                BTC,
                500,
                10,
                0x12d76c5c8ec8edffd3c143995b0aa43fe44a6d71eb9113796272909e54b8e078
            );
            uint8[4] memory config = [0, 2, 0, 2];
            setSwapAdapterToV4SingleSwap(USDC_CBBTC_key, config);
            vm.stopPrank();
        }
    }

    uint256 amountToDep = 2 * 100000 * 1e6; // 200k USDC

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
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        assertTicks(-73458, -67458);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 2338819880825639830372751712, 1e1, "sqrtPrice");
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 14171775946;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);
        assertApproxEqAbs(deltaBTC, 12187249, 1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaBTC, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(122062569, 239999999997, 65801318565, 99915331);
        assertEqProtocolState(2308042746179806544908258638, 199613393074);
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 btcToGetFSwap = 1e7;
        uint256 usdcToSwapQ = quoteUSDC_BTC_Out(btcToGetFSwap);
        assertApproxEqAbs(usdcToSwapQ, 11600600067, 1);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaBTC) = swapUSDC_BTC_Out(btcToGetFSwap);
        assertApproxEqAbs(deltaBTC, btcToGetFSwap, 1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaBTC, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(125179400, 239999999997, 68372494445, 100844912);
        assertEqProtocolState(2313566329004018638409780145, 199552161234);
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 btcToSwap = 1e7;
        deal(address(BTC), address(swapper.addr), btcToSwap);
        assertEqBalanceState(swapper.addr, btcToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapBTC_USDC_In(btcToSwap);
        assertEq(deltaUSDC, 11352758298);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(153679398, 239999999997, 91325852810, 109344911);
        assertEqProtocolState(2364073429387963749880181281, 199549484459);
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14374512916;
        uint256 btcToSwapQ = quoteBTC_USDC_Out(usdcToGetFSwap);
        assertEq(btcToSwapQ, 12698187);

        deal(address(BTC), address(swapper.addr), btcToSwapQ);
        assertEqBalanceState(swapper.addr, btcToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapBTC_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157524313, 239999999997, 94347607427, 110491640);
        assertEqProtocolState(2370887307335613150075615808, 199623990385); //rounding error for sqrt price 1e18????
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
        (, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);
        assertApproxEqAbs(deltaBTC, 12181236, 1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaBTC, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(122071137, 239999999997, 65801318566, 99917886);
        assertEqProtocolState(2308057932347120013680961962, 199620293195);
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 btcToGetFSwap = 1e7;
        uint256 usdcToSwapQ = quoteUSDC_BTC_Out(btcToGetFSwap);
        assertEq(usdcToSwapQ, 11606403270);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaBTC) = swapUSDC_BTC_Out(btcToGetFSwap);
        assertApproxEqAbs(deltaBTC, 10000000, 1e1);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaBTC, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(125179400, 239999999997, 68366691243, 100844912);
        assertEqProtocolState(2313566329004018638409780145, 199557964436);
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);

        // ** Before swap State
        uint256 btcToSwap = 1e7;
        deal(address(BTC), address(swapper.addr), btcToSwap);
        assertEqBalanceState(swapper.addr, btcToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapBTC_USDC_In(btcToSwap);
        assertEq(deltaUSDC, 11352758298);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(153679398, 239999999997, 91325852810, 109344911);
        assertEqProtocolState(2364073429387963749880181281, 199549484459);
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14374512916;
        uint256 btcToSwapQ = quoteBTC_USDC_Out(usdcToGetFSwap);
        assertEq(btcToSwapQ, 12704540);

        deal(address(BTC), address(swapper.addr), btcToSwapQ);
        assertEqBalanceState(swapper.addr, btcToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapBTC_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157533363, 239999999997, 94347607427, 110494339);
        assertEqProtocolState(2370887307335613150075615808, 199631278374); //rounding error for sqrt price 1e18????
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;

        test_deposit_rebalance();
        saveBalance(address(manager));

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_CBBTC_key);

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

            (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                hook.sqrtPriceCurrent()
            );

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaBTC, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - (deltaBTC * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaBTC) / 1e18
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
            (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            assertApproxEqAbs(deltaBTC, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - (deltaBTC * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaBTC) / 1e18
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
            deal(address(BTC), address(swapper.addr), quoteBTC_USDC_Out(usdcToGetFSwap));

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapBTC_USDC_Out(usdcToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                hook.sqrtPriceCurrent()
            );
            assertApproxEqAbs((deltaBTC * (1e18 - testFee)) / 1e18, deltaX, 2);
            assertApproxEqAbs(deltaUSDC, deltaY, 2);

            uint256 deltaTreasuryFee = (deltaBTC * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");

            assertEqPositionState(
                CL + ((deltaBTC - deltaTreasuryFee) * k1) / 1e18,
                CS,
                DL + usdcToGetFSwap,
                DS + ((k1 - 1e18) * (deltaBTC - deltaTreasuryFee)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_CBBTC_key);

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
            uint256 _amountToDep = 100 * 1000 * 1e6; //200 ETH in USDC
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

            uint256 usdcToSwap = 10000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            assertApproxEqAbs(deltaBTC, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 3);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - (deltaBTC * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaBTC) / 1e18
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

            uint256 btcToGetFSwap = 1e6;
            deal(address(USDC), address(swapper.addr), quoteUSDC_BTC_Out(btcToGetFSwap));

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_Out(btcToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaBTC %s", deltaBTC);

            assertApproxEqAbs(deltaBTC, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL - ((deltaBTC) * k1) / 1e18,
                CS,
                DL - deltaUSDC + deltaTreasuryFee,
                DS - ((k1 - 1e18) * (deltaBTC)) / 1e18
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

            uint256 btcToSwap = 1e5;
            deal(address(BTC), address(swapper.addr), btcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapBTC_USDC_In(btcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
            assertApproxEqAbs((deltaBTC * (1e18 - testFee)) / 1e18, deltaX, 3);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaBTC * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeB);

            assertEqPositionState(
                CL + ((deltaBTC - deltaTreasuryFee) * k1) / 1e18,
                CS,
                DL + deltaUSDC,
                DS + ((k1 - 1e18) * (deltaBTC - deltaTreasuryFee)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_CBBTC_key);
        // ** Rebalance
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_CBBTC_key);

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);

            _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        }

        // assertBalanceNotChanged(address(manager), 1e1);
    }

    // ** Helpers

    function quoteUSDC_BTC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function quoteBTC_USDC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapBTC_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, false, amount);
    }

    function swapBTC_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, true, amount);
    }

    function swapUSDC_BTC_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, false, amount);
    }

    function swapUSDC_BTC_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, true, amount);
    }

    function swapAndReturnDeltas(bool zeroForOne, bool isExactInput, uint256 amount) public returns (uint256, uint256) {
        console.log("START: swapAndReturnDeltas");
        int256 usdcBefore = int256(USDC.balanceOf(swapper.addr));
        int256 btcBefore = int256(BTC.balanceOf(swapper.addr));

        vm.startPrank(swapper.addr);
        _swap_v4_single_throw_router(zeroForOne, isExactInput, amount, key);
        vm.stopPrank();

        int256 usdcAfter = int256(USDC.balanceOf(swapper.addr));
        int256 btcAfter = int256(BTC.balanceOf(swapper.addr));
        console.log("END: swapAndReturnDeltas");
        return (abs(usdcAfter - usdcBefore), abs(btcAfter - btcBefore));
    }
}
