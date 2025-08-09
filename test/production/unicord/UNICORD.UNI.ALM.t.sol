// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

// ** contracts
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UNICORD_UNI_ALMTest is ALMTestBaseUnichain {
    uint256 longLeverage = 1e18;
    uint256 shortLeverage = 1e18;
    uint256 weight = 50e16; //50%
    uint256 liquidityMultiplier = 1e18;
    uint256 slippage = 30e14; //0.3%
    uint24 feeLP = 100; //0.01%

    IERC20 USDT = IERC20(UConstants.USDT);
    IERC20 USDC = IERC20(UConstants.USDC);

    function setUp() public {
        select_unichain_fork(23404999);

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
            SLIPPAGE_TOLERANCE_V4 = 1e15;
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        manager = UConstants.manager;
        deployMockUniversalRouter(); // universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER; // deployMockV4Quoter();

        create_accounts_and_tokens(UConstants.USDC, 6, "USDC", UConstants.USDT, 6, "USDT");
        create_lending_adapter_morpho_earn_USDC_USDT_unichain();
        create_flash_loan_adapter_morpho_unichain();

        create_oracle(UConstants.chronicle_feed_USDC, UConstants.chronicle_feed_USDT, true);
        mock_latestRoundData(UConstants.chronicle_feed_USDT, 999620000000000000);
        mock_latestRoundData(UConstants.chronicle_feed_USDC, 999735368664584522);
        init_hook(false, true, liquidityMultiplier, 0, 1000000 ether, 100, 100, TestLib.sqrt_price_1per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(2, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();

        // Re-setup swap router for native-token
        {
            vm.startPrank(deployer.addr);
            uint8[4] memory config = [0, 2, 0, 2];
            setSwapAdapterToV4SingleSwap(USDC_USDT_key_unichain, config);
            vm.stopPrank();
        }
    }

    function test_setUp() public view {
        assertEq(hook.owner(), deployer.addr);
        assertTicks(-100, 100);
    }

    uint256 amountToDep = 100000e6;

    function test_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(USDT), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, amountToDep, 1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEqProtocolState(initialSQRTPrice, 99999999999);
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        test_deposit();

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        assertTicks(-99, 101);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 79232734343355120339899722311, 1e1, "sqrtPrice");
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 17897776432;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
        assertApproxEqAbs(deltaUSDT, 17836169721, 1, "USDT");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(32302956123, 67742023776, 0, 0);
        assertEqProtocolState(78950892006377058077331884639, 100052798176);
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToGetFSwap = 17897776432;
        uint256 usdcToSwapQ = quoteUSDC_USDT_Out(usdtToGetFSwap);
        assertEq(usdcToSwapQ, 17959817385);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaUSDT) = swapUSDC_USDT_Out(usdtToGetFSwap);
        assertApproxEqAbs(deltaUSDT, 17897776432, 1e1, "USDT");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(32241349412, 67804064729, 0, 0);
        assertEqProtocolState(78949918513778550882947841077, 100053239579);
    }

    function test_deposit_rebalance_swap_price_up_out_revert_deviations() public {
        vm.startPrank(deployer.addr);
        updateProtocolPriceThreshold(3 * 1e15);
        vm.stopPrank();
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToGetFSwap = 200e9;

        // SwapPriceChangeTooHigh
        bool hasReverted = false;
        try this.swapUSDC_USDT_Out(usdtToGetFSwap) {
            hasReverted = false;
        } catch {
            hasReverted = true;
        }
        assertTrue(hasReverted, "Expected function to revert but it didn't");
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToSwap = 17897776432;
        deal(address(USDT), address(swapper.addr), usdtToSwap);
        assertEqBalanceState(swapper.addr, usdtToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapUSDT_USDC_In(usdtToSwap);
        assertEq(deltaUSDC, 17832060720);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(68036902277, 32012186624, 0, 0);
        assertEqProtocolState(79515550172922265623323628034, 100052783508);
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 17987491283;
        uint256 usdtToSwapQ = quoteUSDT_USDC_Out(usdcToGetFSwap);
        assertEq(usdtToSwapQ, 18054341510);

        deal(address(USDT), address(swapper.addr), usdtToSwapQ);
        assertEqBalanceState(swapper.addr, usdtToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapUSDT_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(68193467355, 31856756062, 0, 0);
        assertEqProtocolState(79518024172000438730060968108, 100053900085);
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 17897776432;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
        assertApproxEqAbs(deltaUSDT, 17834392448, 1e4, "USDT");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(32304733396, 67742023775, 0, 0);
        assertEqProtocolState(78950920090370935380564870342, 100054575448);
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToGetFSwap = 17897776432;
        uint256 usdcToSwapQ = quoteUSDC_USDT_Out(usdtToGetFSwap);
        assertEq(usdcToSwapQ, 17961613547);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaUSDT) = swapUSDC_USDT_Out(usdtToGetFSwap);
        assertApproxEqAbs(deltaUSDT, 17897776432, 1e1, "USDT");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(32241349412, 67805860890, 0, 0);
        assertEqProtocolState(78949918513778550882947841077, 100055035947);
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToSwap = 17897776432;
        deal(address(USDT), address(swapper.addr), usdtToSwap);
        assertEqBalanceState(swapper.addr, usdtToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapUSDT_USDC_In(usdtToSwap);
        assertEq(deltaUSDC, 17830283856);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(68036902276, 32013963489, 0, 0);
        assertEqProtocolState(79515521891333670851555441055, 100054560577);
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 17987491283;
        uint256 usdtToSwapQ = quoteUSDT_USDC_Out(usdcToGetFSwap);
        assertEq(usdtToSwapQ, 18056147125);

        deal(address(USDT), address(swapper.addr), usdtToSwapQ);
        assertEqBalanceState(swapper.addr, usdtToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapUSDT_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(68195272969, 31856756062, 0, 0);
        assertEqProtocolState(79518024172000438730060968108, 100055705699);
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

        // ** Swap Up In
        {
            uint256 usdcToSwap = 10000e6; // 1k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaUSDT, deltaX, 2);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 2);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaUSDT, deltaX, 2);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 2);
        }

        // ** Swap Down Out
        {
            uint256 usdcToGetFSwap = 10000e6; //10k USDC
            uint256 usdtToSwapQ = quoteUSDT_USDC_Out(usdcToGetFSwap);
            deal(address(USDT), address(swapper.addr), usdtToSwapQ);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDT_USDC_Out(usdcToGetFSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);
            assertApproxEqAbs((deltaUSDT * (1e18 - testFee)) / 1e18, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

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

        // ** Swap Up In
        {
            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);
            assertApproxEqAbs(deltaUSDT, deltaX, 1);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

        // ** Deposit
        {
            uint256 _amountToDep = 100000e6; //100k USDC
            deal(address(USDT), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            hook.deposit(alice.addr, _amountToDep, 0);
        }

        // ** Swap Down In
        {
            uint256 usdtToSwap = 10000e6;
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDT_USDC_In(usdtToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);
            assertApproxEqAbs((deltaUSDT * (1e18 - testFee)) / 1e18, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
        }

        // ** Swap Up Out
        {
            uint256 usdtToGetFSwap = 10000e6; //10k USDT
            uint256 usdcToSwapQ = quoteUSDC_USDT_Out(usdtToGetFSwap);
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDC_USDT_Out(usdtToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
            assertApproxEqAbs(deltaUSDT, deltaX, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 3);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

        // ** Rebalance
        {
            uint256 preRebalanceTVL = calcTVL();
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);
            _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);

            uint256 calcCL = (preRebalanceTVL * weight) / 1e18;
            uint256 afterCL = lendingAdapter.getCollateralLong();
            uint256 ratioCL = afterCL > calcCL
                ? ((afterCL * 1e18) / calcCL - 1e18)
                : ((calcCL * 1e18) / afterCL - 1e18);

            // ** small deviation is allowed
            require(ratioCL < (slippage * 12e17) / 1e18);

            uint256 calcCS = (preRebalanceTVL * (1e18 - weight)) / 1e18;
            uint256 afterCS = lendingAdapter.getCollateralShort();
            uint256 ratioCS = afterCS > calcCS
                ? ((afterCS * 1e18) / calcCS - 1e18)
                : ((calcCS * 1e18) / afterCS - 1e18);

            // ** small deviation is allowed
            require(ratioCS < (slippage * 12e17) / 1e18);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        }
    }

    // ** Helpers

    function swapUSDT_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, false, amount);
    }

    function quoteUSDT_USDC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapUSDT_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, true, amount);
    }

    function swapUSDC_USDT_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, false, amount);
    }

    function quoteUSDC_USDT_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function swapUSDC_USDT_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, true, amount);
    }

    function swapAndReturnDeltas(bool zeroForOne, bool isExactInput, uint256 amount) public returns (uint256, uint256) {
        console.log("START: swapAndReturnDeltas");
        int256 usdtBefore = int256(USDT.balanceOf(swapper.addr));
        int256 usdcBefore = int256(USDC.balanceOf(swapper.addr));

        vm.startPrank(swapper.addr);
        _swap_v4_single_throw_router(zeroForOne, isExactInput, amount, key);
        vm.stopPrank();

        int256 usdtAfter = int256(USDT.balanceOf(swapper.addr));
        int256 usdcAfter = int256(USDC.balanceOf(swapper.addr));
        console.log("END: swapAndReturnDeltas");
        return (abs(usdcAfter - usdcBefore), abs(usdtAfter - usdtBefore));
    }
}
