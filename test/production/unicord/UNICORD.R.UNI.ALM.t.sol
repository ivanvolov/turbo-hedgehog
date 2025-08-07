// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

// ** contracts
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UNICORD_R_UNI_ALMTest is ALMTestBaseUnichain {
    uint256 longLeverage = 1e18;
    uint256 shortLeverage = 1e18;
    uint256 weight = 50e16; //50%
    uint256 liquidityMultiplier = 1e18;
    uint256 slippage = 10e14; //0.1%
    uint24 feeLP = 100; //0.01%

    IERC20 WETH = IERC20(UConstants.WETH);
    IERC20 WSTETH = IERC20(UConstants.WSTETH);

    function setUp() public {
        select_unichain_fork(23567130);

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
            SLIPPAGE_TOLERANCE_V4 = 1e15;
            IS_NTS = true;
        }

        initialSQRTPrice = 72023797561498541009787625775;
        manager = UConstants.manager;
        deployMockUniversalRouter(); // universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER; // deployMockV4Quoter();

        create_accounts_and_tokens(UConstants.WETH, 18, "WETH", UConstants.WSTETH, 18, "WSTETH"); // isReversePool = true if pool is BASE:QUOTE.
        create_lending_adapter_euler_WETH_WSTETH_unichain();
        create_flash_loan_adapter_morpho_unichain();
        oracle = _create_oracle_one_feed(
            UConstants.zero_feed,
            UConstants.chronicle_feed_WSTETH,
            24 hours,
            false,
            int8(-18)
        );
        isInvertedPool = true; // TODO: remove.
        mock_latestRoundData(UConstants.chronicle_feed_WSTETH, 1210060639502790000);
        init_hook(false, true, liquidityMultiplier, 0, 100000 ether, 100, 100, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(2, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();

        // Re-setup swap router for v4 swaps.
        {
            vm.startPrank(deployer.addr);
            uint8[4] memory config = [1, 2, 1, 2];
            setSwapAdapterToV4SingleSwap(ETH_WSTETH_key_unichain, config);
            vm.stopPrank();
        }

        // Check oracle alignment.
        {
            (uint256 price, uint256 sqrtPriceX96) = oracle.poolPrice();
            console.log("price %s", price);
            console.log("sqrtPrice %s", sqrtPriceX96);
            console.log(getV4PoolSQRTPrice(ETH_WSTETH_key_unichain));
        }
    }

    uint256 amountToDep = 100e18; // 1M

    function test_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(WSTETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, amountToDep, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep - 1, 0, 0, 0);
        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(calcTVL(), amountToDep, 1e1, "tvl");
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        test_deposit();

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        // assertEqBalanceStateZero(address(hook));
        // console.log("tvl %s", calcTVL());

        // console.log("liquidity %s", hook.liquidity());
        // (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        // console.log("tickLower %s", tickLower);
        // console.log("tickUpper %s", tickUpper);
        // assertTicks(-276421, -276221);
        // assertApproxEqAbs(hook.sqrtPriceCurrent(), 79240362711883211369901, 1e1, "sqrtPrice");
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();

        alignOraclesAndPoolsV4(hook, ETH_WSTETH_key_unichain);

        // ** Make oracle change with swap price
        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;
        uint256 treasuryFeeB;
        uint256 treasuryFeeQ;

        // ** Swap Down In
        {
            console.log("SWAP UP IN");

            uint256 ethToSwap = 10e18; // 1k ETH
            deal(address(swapper.addr), ethToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWSTETH, uint256 deltaETH) = swapETH_WSTETH_In(ethToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            console.log("deltaWSTETH %s", deltaWSTETH);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWSTETH, deltaX, 1);
            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 1);

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            uint256 deltaTreasuryFee = (deltaETH * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");
        }

        // ** Swap Down In
        {
            console.log("SWAP UP IN");

            uint256 ethToSwap = 3e18; // 10k ETH
            deal(address(swapper.addr), ethToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWSTETH, uint256 deltaETH) = swapETH_WSTETH_In(ethToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaWSTETH, deltaX, 1);
            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 1);

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            uint256 deltaTreasuryFee = (deltaETH * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }

        // ** Swap Up Out
        {
            console.log("SWAP DOWN OUT");

            uint256 usdcToGetFSwap = 5e18; //10k ETH
            uint256 wstethToSwapQ = quoteWSTETH_ETH_Out(usdcToGetFSwap);

            console.log("wstethToSwapQ %s", wstethToSwapQ);

            deal(address(WSTETH), address(swapper.addr), wstethToSwapQ);
            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaWSTETH, uint256 deltaETH) = swapWSTETH_ETH_Out(usdcToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            assertApproxEqAbs((deltaWSTETH * (1e18 - testFee)) / 1e18, deltaX, 1);
            assertApproxEqAbs(deltaETH, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaWSTETH * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_WSTETH_key_unichain);

        // ** Withdraw
        {
            console.log("preTVL %s", calcTVL());
            console.log("preBalance %s", WSTETH.balanceOf(alice.addr));
            console.log("preBalance %s", WETH.balanceOf(alice.addr));

            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 5, 0, 0);

            console.log("postTVL %s", calcTVL());
            console.log("postBalance %s", WSTETH.balanceOf(alice.addr));
            console.log("postBalance %s", WETH.balanceOf(alice.addr));
        }

        // ** Swap Down In
        {
            console.log("SWAP UP IN");

            uint256 ethToSwap = 5e18; // 10k ETH
            deal(address(swapper.addr), ethToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWSTETH, uint256 deltaETH) = swapETH_WSTETH_In(ethToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaWSTETH, deltaX, 1);
            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 1);

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            uint256 deltaTreasuryFee = (deltaETH * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 3, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }
        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_WSTETH_key_unichain);

        // ** Deposit
        {
            uint256 _amountToDep = 10e18; //10k ETH
            deal(address(WSTETH), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            hook.deposit(alice.addr, _amountToDep, 0);
        }

        // ** Swap Down In
        {
            console.log("SWAP UP IN");

            uint256 ethToSwap = 1e18; // 10k ETH
            deal(address(swapper.addr), ethToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWSTETH, uint256 deltaETH) = swapETH_WSTETH_In(ethToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaWSTETH, deltaX, 1);
            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 1);

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            uint256 deltaTreasuryFee = (deltaETH * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 4, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }

        // ** Swap Down out
        {
            uint256 wstethToGetFSwap = 3e18; //1k WSTETH
            uint256 ethToSwapQ = quoteETH_WSTETH_Out(wstethToGetFSwap);
            console.log("ETH balance pre %s", WETH9.balanceOf(address(this)));
            console.log("ethToSwapQ", ethToSwapQ);
            deal(address(swapper.addr), ethToSwapQ);
            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("ETH balance after %s", WETH9.balanceOf(address(this)));

            (uint256 deltaWSTETH, uint256 deltaETH) = swapETH_WSTETH_Out(wstethToGetFSwap - 1);

            console.log("deltaWSTETH", deltaWSTETH);
            console.log("deltaETH", deltaETH);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            assertApproxEqAbs(deltaWSTETH, deltaX, 1);
            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 1);

            uint256 deltaTreasuryFee = (deltaETH * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 4, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }
        // ** Swap Up In
        {
            uint256 wstethToSwap = 10e18;
            deal(address(WSTETH), address(swapper.addr), wstethToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWSTETH, uint256 deltaETH) = swapWSTETH_ETH_In(wstethToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaWSTETH", deltaWSTETH);
            console.log("deltaETH", deltaETH);
            console.log("deltaX", deltaX);
            console.log("deltaY", deltaY);

            assertApproxEqAbs((deltaWSTETH * (1e18 - testFee)) / 1e18, deltaX, 1);
            assertApproxEqAbs(deltaETH, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_WSTETH_key_unichain);

        // ** Rebalance
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_WSTETH_key_unichain);

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        }
    }

    // ** Helpers

    function swapWSTETH_ETH_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, false, amount);
    }

    function quoteWSTETH_ETH_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapWSTETH_ETH_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(false, true, amount);
    }

    function swapETH_WSTETH_Out(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, false, amount);
    }

    function quoteETH_WSTETH_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function swapETH_WSTETH_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, true, amount);
    }

    function swapAndReturnDeltas(bool zeroForOne, bool isExactInput, uint256 amount) public returns (uint256, uint256) {
        console.log("START: swapAndReturnDeltas");
        int256 wstethBefore = int256(WSTETH.balanceOf(swapper.addr));
        int256 ethBefore = int256((swapper.addr).balance);

        vm.startPrank(swapper.addr);
        _swap_v4_single_throw_router(zeroForOne, isExactInput, amount, key);
        vm.stopPrank();

        int256 wstethAfter = int256(WSTETH.balanceOf(swapper.addr));
        int256 ethAfter = int256((swapper.addr).balance);
        console.log("END: swapAndReturnDeltas");
        return (abs(wstethBefore - wstethAfter), abs(ethAfter - ethBefore));
    }
}
