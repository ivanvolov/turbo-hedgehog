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

contract BTC_BASE_ALMTest is ALMTestBaseBase {
    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 50e16;
    uint256 liquidityMultiplier = 1e18;
    uint256 slippage = 10e15;
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
            ASSERT_EQ_PS_THRESHOLD_CL = 1e2;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e2;
            isNTS = 2;
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        manager = BConstants.manager;
        deployMockUniversalRouter(); // universalRouter = BConstants.UNIVERSAL_ROUTER;
        quoter = BConstants.V4_QUOTER; // deployMockV4Quoter();

        create_accounts_and_tokens(BConstants.USDC, 6, "USDC", BConstants.CBBTC, 8, "CBBTC");
        create_flash_loan_adapter_morpho_base();
        create_lending_adapter_euler_USDC_BTC_base();

        create_oracle(BConstants.chainlink_feed_USDC, BConstants.chainlink_feed_CBBTC, true);
        init_hook(false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            // hook.setNextLPFee(0); // By default, dynamic-fee-pools initialize with a 0% fee, to change - call rebalance.
            positionManager.setKParams(k1, k2); // 1.425 1.425
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(TestLib.ONE_PERCENT_AND_ONE_BPS, 2000, 2e17, 2e17); // 0.2 (2%), 0.2 (2%)
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

    uint256 amountToDep = 1 * 1e8;

    function test_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(BTC), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, amountToDep, 1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEqProtocolState(initialSQRTPrice, 1e8);
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        test_deposit();

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);

        assertEqBalanceStateZero(address(hook));
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        assertTicks(-73458, -67458);
        console.log("oraclePrice %s", oracle.price());
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 2338819880825639830372751712, 1e1, "sqrtPrice");
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        updateProtocolFees(20 * 1e16); // 20% from fees
        hook.setNextLPFee(feeLP);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
        vm.stopPrank();

        test_deposit_rebalance();
        saveBalance(address(manager));

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;
        uint256 treasuryFeeB;
        uint256 treasuryFeeQ;

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_CBBTC_key);

        // ** Swap Up In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdcToSwap = 2683e6; // 2683 USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);
            console.log("liquidity %s", hook.liquidity());

            (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaBTC %s", deltaBTC);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaBTC, deltaX, 3);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 4);

            uint256 deltaTreasuryFee = (usdcToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            console.log("treasuryFee BASE %s", treasuryFeeB);
            console.log("treasuryFee QUOTE %s", treasuryFeeQ);

            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            assertEqPositionState(
                CL - ((deltaBTC) * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * (deltaBTC)) / 1e18
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

            uint256 usdcToSwap = 5e9; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);
            (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaBTC %s", deltaBTC);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaBTC, deltaX, 1);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 2);

            uint256 deltaTreasuryFee = (usdcToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            console.log("treasuryFee BASE %s", treasuryFeeB);
            console.log("treasuryFee QUOTE %s", treasuryFeeQ);

            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            assertEqPositionState(
                CL - ((deltaBTC) * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * (deltaBTC)) / 1e18
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

            uint256 usdcToGetFSwap = 10e9; //10k USDC
            deal(address(BTC), address(swapper.addr), quoteBTC_USDC_Out(usdcToGetFSwap));

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapBTC_USDC_Out(usdcToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaBTC %s", deltaBTC);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs((deltaBTC * (1e18 - testFee)) / 1e18, deltaX, 2);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaX * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");

            assertEqPositionState(
                CL + ((deltaBTC - deltaTreasuryFee) * k1) / 1e18,
                CS,
                DL + deltaUSDC,
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

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_CBBTC_key);

        // ** Deposit
        {
            uint256 _amountToDep = 1e8;
            deal(address(BTC), address(alice.addr), _amountToDep);
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

            uint256 usdcToSwap = 5e9; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);
            (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaBTC %s", deltaBTC);
            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaBTC, deltaX, 2);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 4);

            uint256 deltaTreasuryFee = (usdcToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            console.log("treasuryFee BASE %s", treasuryFeeB);
            console.log("treasuryFee QUOTE %s", treasuryFeeQ);

            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            assertEqPositionState(
                CL - ((deltaBTC) * k1) / 1e18,
                CS,
                DL - usdcToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * (deltaBTC)) / 1e18
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

            uint256 btcToGetFSwap = 5e6;
            deal(address(USDC), address(swapper.addr), quoteUSDC_BTC_Out(btcToGetFSwap));

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_Out(btcToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            assertApproxEqAbs(deltaBTC, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);

            uint256 deltaTreasuryFeeB = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFeeB;

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 3, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 3, "treasuryFee");

            assertEqPositionState(
                CL - ((deltaBTC) * k1) / 1e18,
                CS,
                DL - deltaUSDC + deltaTreasuryFeeB,
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

            uint256 btcToSwap = 5e6;
            deal(address(BTC), address(swapper.addr), btcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapBTC_USDC_In(btcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
            console.log("deltaX %s", deltaX);
            assertApproxEqAbs((deltaBTC * (1e18 - testFee)) / 1e18, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);

            uint256 deltaTreasuryFeeQ = (deltaX * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFeeQ;

            //treasuryFeeB += deltaTreasuryFeeB;
            console.log("treasuryFeeB %s", hook.accumulatedFeeB());
            console.log("deltaTreasuryFeeB %s", deltaTreasuryFeeQ);

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 3, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 3, "treasuryFee");

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            //console.log("deltaTreasuryFeeQ %s", treasuryFeeB);

            assertEqPositionState(
                CL + ((deltaBTC - deltaTreasuryFeeQ) * k1) / 1e18,
                CS,
                DL + deltaUSDC,
                DS + ((k1 - 1e18) * (deltaBTC - deltaTreasuryFeeQ)) / 1e18
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

    function swapBTC_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, false, amount);
    }

    function quoteBTC_USDC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapBTC_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, true, amount);
    }

    function swapUSDC_BTC_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, false, amount);
    }

    function quoteUSDC_BTC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
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
