// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

// ** interfaces
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// This test illustrates the pool with the reversed order of currencies. The main asset first and the stable next.
contract ETH_R2_UNI_ALMTest is ALMTestBaseUnichain {
    uint256 longLeverage = 2e18;
    uint256 shortLeverage = 1e18;
    uint256 weight = 55e16; //50%
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 40e14; //0.40%
    uint24 feeLP = 500; //0.05%

    uint256 k1 = 1e18; //1.425
    uint256 k2 = 1e18; //1.425

    IERC20 WETH = IERC20(UConstants.WETH);
    IERC20 USDT = IERC20(UConstants.USDT);
    PoolKey ETH_USDT_key;

    function setUp() public {
        select_unichain_fork(23128176);

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

        create_accounts_and_tokens(UConstants.USDT, 6, "USDT", UConstants.WETH, 18, "WETH");
        create_flash_loan_adapter_morpho_unichain();
        create_lending_adapter_euler_USDT_WETH_unichain();
        oracle = _create_oracle(
            UConstants.chronicle_feed_WETH,
            UConstants.chronicle_feed_USDT,
            24 hours,
            24 hours,
            false,
            int8(6 - 18)
        );
        mock_latestRoundData(address(UConstants.chronicle_feed_WETH), 3754570000000000000000);
        mock_latestRoundData(address(UConstants.chronicle_feed_USDT), 999983595619733749);
        production_init_hook(false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);

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

        approve_accounts();

        // Re-setup swap router for native-token
        {
            vm.startPrank(deployer.addr);
            ETH_USDT_key = _getAndCheckPoolKey(
                ETH,
                USDT,
                500,
                10,
                0x04b7dd024db64cfbe325191c818266e4776918cd9eaf021c26949a859e654b16
            );
            uint8[4] memory config = [2, 1, 2, 3];
            setSwapAdapterToV4SingleSwap(ETH_USDT_key, config);
            vm.stopPrank();
        }
    }

    function test_setUp() public {
        vm.skip(true);
        assertEq(hook.owner(), deployer.addr);
        assertTicks(-200488, -194488);
    }

    uint256 amountToDep = 100 ether;

    function part_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, amountToDep, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEqProtocolState(initialSQRTPrice, amountToDep);
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function part_deposit_rebalance() public {
        part_deposit();

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
        console.log("postRebalanceTVL %s", calcTVL());
        console.log("oraclePrice %s", oracle.price());
        console.log("sqrtPrice %s", hook.sqrtPriceCurrent());

        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        console.log("our liquidity %s", hook.liquidity());
        assertTicks(-197013, -191013);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 4854709515966874528458964, 1, "sqrtPrice");
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        part_deposit_rebalance();
        console.log("DEPOSIT REBALANCE");

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDT_key);

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;
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

            uint256 usdtToSwap = 50000e6; // 50k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("SWAP");
            (uint256 deltaETH, uint256 deltaUSDT) = swapUSDT_ETH_In(usdtToSwap);
            console.log("SWAP DONE");
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaUSDT %s", deltaUSDT);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaETH, deltaY, 1);
            assertApproxEqAbs((usdtToSwap * (1e18 - testFee)) / 1e18, deltaX, 4);

            uint256 deltaTreasuryFee = (usdtToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            assertEqPositionState(
                CL - (deltaETH * k1) / 1e18,
                CS,
                DL - usdtToSwap + deltaTreasuryFee,
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

            uint256 usdtToSwap = 10e9; // 10k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaETH, uint256 deltaUSDT) = swapUSDT_ETH_In(usdtToSwap);
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaUSDT %s", deltaUSDT);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaETH, deltaY, 1);
            assertApproxEqAbs((usdtToSwap * (1e18 - testFee)) / 1e18, deltaX, 1);

            uint256 deltaTreasuryFee = (usdtToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            assertEqPositionState(
                CL - (deltaETH * k1) / 1e18,
                CS,
                DL - usdtToSwap + deltaTreasuryFee,
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

            uint256 usdtToGetFSwap = 20000e6; //20k USDT

            deal(address(swapper.addr), quoteETH_USDT_Out(usdtToGetFSwap));

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaETH, uint256 deltaUSDT) = swapETH_USDT_Out(usdtToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaUSDT %s", deltaUSDT);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaUSDT, deltaX, 1);
            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 4);

            uint256 deltaTreasuryFee = (deltaETH * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");

            console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertEqPositionState(
                CL + ((deltaETH - deltaTreasuryFee) * k1) / 1e18,
                CS,
                DL + deltaUSDT,
                DS + ((k1 - 1e18) * (deltaETH - deltaTreasuryFee)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDT_key);

        // ** Withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 2, 0, 0);
            _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        }

        // ** Swap Up In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdtToSwap = 10e9; // 10k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaETH, uint256 deltaUSDT) = swapUSDT_ETH_In(usdtToSwap);
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaUSDT %s", deltaUSDT);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaETH, deltaY, 1);
            assertApproxEqAbs((usdtToSwap * (1e18 - testFee)) / 1e18, deltaX, 1);

            uint256 deltaTreasuryFee = (usdtToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");

            assertEqPositionState(
                CL - (deltaETH * k1) / 1e18,
                CS,
                DL - usdtToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaETH) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDT_key);

        // ** Deposit
        {
            uint256 _amountToDep = 200 ether;
            deal(address(WETH), address(alice.addr), _amountToDep);
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

            uint256 usdtToSwap = 10e9; // 10k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaETH, uint256 deltaUSDT) = swapUSDT_ETH_In(usdtToSwap);
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaUSDT %s", deltaUSDT);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaETH, deltaY, 1);
            assertApproxEqAbs((usdtToSwap * (1e18 - testFee)) / 1e18, deltaX, 1);

            uint256 deltaTreasuryFee = (usdtToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");

            assertEqPositionState(
                CL - (deltaETH * k1) / 1e18,
                CS,
                DL - usdtToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaETH) / 1e18
            );
        }

        // ** Swap Up out
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 ethToGetFSwap = 1e18;
            deal(address(USDT), address(swapper.addr), quoteUSDT_ETH_Out(ethToGetFSwap));

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaETH, uint256 deltaUSDT) = swapUSDT_ETH_Out(ethToGetFSwap);
            console.log("SWAP DONE");
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaUSDT %s", deltaUSDT);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs((deltaUSDT * (1e18 - testFee)) / 1e18, deltaX, 1);
            assertApproxEqAbs(deltaETH, deltaY, 1);

            uint256 deltaTreasuryFeeB = (deltaUSDT * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFeeB;

            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 3, "treasuryFee");
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            assertEqPositionState(
                CL - ((deltaETH) * k1) / 1e18,
                CS,
                DL - deltaUSDT + deltaTreasuryFeeB,
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

            console.log("CL %s", CL);
            console.log("DL %s", DL);

            uint256 ethToSwap = 10e18;
            deal(address(swapper.addr), ethToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaETH, uint256 deltaUSDT) = swapETH_USDT_In(ethToSwap);
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaUSDT %s", deltaUSDT);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaUSDT, deltaX, 3);
            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 4);

            uint256 deltaTreasuryFeeQ = (deltaETH * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFeeQ;
            console.log("deltaETH %s", deltaETH);
            console.log("testFee %s", testFee);
            console.log("hook.protocolFee() %s", hook.protocolFee());

            console.log("deltaTreasuryFeeQ %s", deltaTreasuryFeeQ);

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 3, "treasuryFee");
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            assertEqPositionState(
                CL + ((deltaETH - deltaTreasuryFeeQ) * k1) / 1e18,
                CS,
                DL + deltaUSDT,
                DS + ((k1 - 1e18) * (deltaETH - deltaTreasuryFeeQ)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDT_key);

        // ** Rebalance
        uint256 preRebalanceTVL = calcTVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage * 2);

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDT_key);

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
            _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        }
    }

    // ** Helpers

    function swapETH_USDT_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, false, amount);
    }

    function quoteETH_USDT_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function swapETH_USDT_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, true, amount);
    }

    function swapUSDT_ETH_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, false, amount);
    }

    function quoteUSDT_ETH_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapUSDT_ETH_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, true, amount);
    }

    function swapAndReturnDeltas(bool zeroForOne, bool isExactInput, uint256 amount) public returns (uint256, uint256) {
        console.log("START: swapAndReturnDeltas");
        int256 usdtBefore = int256(USDT.balanceOf(swapper.addr));
        int256 ethBefore = int256(swapper.addr.balance);

        vm.startPrank(swapper.addr);
        _swap_v4_single_throw_router(zeroForOne, isExactInput, amount, key);
        vm.stopPrank();

        int256 usdtAfter = int256(USDT.balanceOf(swapper.addr));
        int256 ethAfter = int256(swapper.addr.balance);
        console.log("END: swapAndReturnDeltas");
        return (abs(ethAfter - ethBefore), abs(usdtAfter - usdtBefore));
    }
}
