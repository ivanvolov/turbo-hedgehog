// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityAmounts} from "v4-core-test/utils/LiquidityAmounts.sol";

// ** contracts
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";
import {ALM} from "@src/ALM.sol";
import {BaseStrategyHook} from "@src/core/base/BaseStrategyHook.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {TestLib} from "@test/libraries/TestLib.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

// ** interfaces
import {IFlashLoanAdapter} from "@src/interfaces/IFlashLoanAdapter.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IOracleTest} from "@test/interfaces/IOracleTest.sol";
import {IPositionManagerStandard} from "@test/interfaces/IPositionManagerStandard.sol";

contract PRE_DEPOSIT_UNI_ALMTest is ALMTestBaseUnichain {
    uint256 longLeverage = 2e18;
    uint256 shortLeverage = 1e18;
    uint256 weight = 9e17;
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 5e15; //0.5%
    uint24 feeLP = 500; //0.05%

    IERC20 WETH = IERC20(UConstants.WETH);
    IERC20 USDC = IERC20(UConstants.USDC);

    address deployerAddress;

    function setUp() public {
        select_unichain_fork(30484160);

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
            IS_NTS = true;
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        manager = UConstants.manager;
        universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER;

        create_accounts_and_tokens(UConstants.USDC, 6, "USDC", UConstants.WETH, 18, "WETH");
        create_flash_loan_adapter_morpho_unichain();
        create_lending_adapter_euler_USDC_WETH_unichain();

        create_oracle(UConstants.chronicle_feed_USDC, UConstants.chronicle_feed_WETH, false);
        mock_latestRoundData(UConstants.chronicle_feed_WETH, UConstants.api3_feed_WETH_price);
        mock_latestRoundData(UConstants.chronicle_feed_USDC, UConstants.api3_feed_USDC_price);

        init_hook(false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.SQRT_PRICE_10PER);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            positionManager.setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(TestLib.ONE_PERCENT_AND_ONE_BPS, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();

        // Re-setup swap router for native-token
        {
            vm.startPrank(deployer.addr);
            uint8[4] memory config = [0, 1, 2, 3];
            setSwapAdapterToV4SingleSwap(ETH_USDC_key_unichain, config);
            vm.stopPrank();
        }
    }

    uint256 amountToDep = 10 ether;

    function test_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        uint256 shares = alm.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, amountToDep, 1e1);
        assertEq(alm.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqBalanceStateZero(address(alm));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEqProtocolState(initialSQRTPrice, amountToDep);
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        test_deposit();

        uint256 preRebalanceTVL = calcTVL();
        console.log("preRebalanceTVL %s", preRebalanceTVL);

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        assertEqBalanceStateZero(address(alm));
        console.log("postRebalanceTVL %s", calcTVL());
        console.log("oraclePrice %s", oracle.price());
        console.log("sqrtPrice %s", hook.sqrtPriceCurrent());
        assertTicks(-196748, -190748);

        assertApproxEqAbs(hook.sqrtPriceCurrent(), 4919520778899813658844498, 1e1, "sqrtPrice");
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
        assertEq(hook.liquidity(), 7423380454458728, "liquidity");
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
    }

    //TODO Yevhen: uncomment all and make it work.
    function test_lifecycle() public {
        test_deposit_rebalance();
        part_pre_deposit_lifecycle();

        // ** Move ALM from Pre-deposit to active mode
        {
            vm.startPrank(deployer.addr);
            alm.setStatus(1); // paused

            rebalanceAdapter.setRebalanceParams(55e16, 3e18, 2e18);
            hook.setOperator(address(0));
            hook.setNextLPFee(feeLP);
            //TODO: do wee need it here? why we need it here?
            rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)

            alm.setStatus(0); // active
            vm.stopPrank();
        }

        // ** Do rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);
            // assertEqBalanceStateZero(address(hook));
            // assertEqBalanceStateZero(address(alm));
            // console.log("postRebalanceTVL %s", calcTVL());
            // console.log("oraclePrice %s", oracle.price());
            // console.log("sqrtPrice %s", hook.sqrtPriceCurrent());
            // assertTicks(-196748, -190748);

            // assertApproxEqAbs(hook.sqrtPriceCurrent(), 4919520778899813658844498, 1e1, "sqrtPrice");
            // alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);
            // assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
            // assertEq(hook.liquidity(), 7423380454458728, "liquidity");
            // _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        }
        part_general_lifecycle();
    }

    function part_pre_deposit_lifecycle() public {
        // ** Deposit
        {
            deal(address(WETH), address(alice.addr), amountToDep);
            uint256 sharesBefore = alm.balanceOf(alice.addr);
            console.log("sharesBefore %s", sharesBefore);
            vm.prank(alice.addr);
            uint256 shares = alm.deposit(alice.addr, amountToDep, 0);

            console.log("shares %s", shares);
            // assertApproxEqAbs(shares, amountToDep, 1e1);
            // assertEq(alm.balanceOf(alice.addr), shares + sharesBefore, "shares on user");
            assertEqBalanceStateZero(alice.addr);
            assertEqBalanceStateZero(address(hook));
            assertEqBalanceStateZero(address(alm));

            // assertEqPositionState(amountToDep * 2, 0, 0, 0);
            // assertEqProtocolState(initialSQRTPrice, amountToDep * 2);
            // assertEq(hook.liquidity(), 0, "liquidity");
        }

        // ** Withdraw
        {
            uint256 sharesToWithdraw = alm.balanceOf(alice.addr);
            vm.prank(alice.addr);
            alm.withdraw(alice.addr, sharesToWithdraw / 3, 0, 0);

            // (int24 tickLower, int24 tickUpper) = hook.activeTicks();
            // uint128 liquidityCheck = LiquidityAmounts.getLiquidityForAmount0(
            //     ALMMathLib.getSqrtPriceX96FromTick(tickLower),
            //     ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
            //     lendingAdapter.getCollateralLong()
            // );

            // console.log("liquidity %s", hook.liquidity());
            // console.log("liquidityCheck %s", liquidityCheck);

            // assertApproxEqAbs(hook.liquidity(), (liquidityCheck * liquidityMultiplier) / 1e18, 1);
        }
    }

    function part_general_lifecycle() public {
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        saveBalance(address(manager));

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;

        // ** Swap Up In
        {
            uint256 usdcToSwap = 10000e6; // 100k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaETH, deltaY, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 4);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaETH %s", deltaETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaETH, deltaY, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 2);
        }

        // ** Swap Down Out
        {
            uint256 usdcToGetFSwap = 10000e6; //10k USDC
            uint256 ethToSwapQ = quoteETH_USDC_Out(usdcToGetFSwap);

            deal(address(swapper.addr), ethToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapETH_USDC_Out(usdcToGetFSwap);

            // uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            // (uint256 deltaX, uint256 deltaY) = _checkSwap(
            //     hook.liquidity(),
            //     uint160(preSqrtPrice),
            //     uint160(postSqrtPrice)
            // );

            // console.log("deltaUSDC %s", deltaUSDC);
            // console.log("deltaETH %s", deltaETH);
            // console.log("deltaX %s", deltaX);
            // console.log("deltaY %s", deltaY);

            // assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 2);
            // assertApproxEqAbs(deltaUSDC, deltaX, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

        // ** Withdraw
        {
            uint256 sharesToWithdraw = alm.balanceOf(alice.addr);
            vm.prank(alice.addr);
            alm.withdraw(alice.addr, sharesToWithdraw / 2, 0, 0);

            // (int24 tickLower, int24 tickUpper) = hook.activeTicks();
            // uint128 liquidityCheck = LiquidityAmounts.getLiquidityForAmount0(
            //     ALMMathLib.getSqrtPriceX96FromTick(tickLower),
            //     ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
            //     lendingAdapter.getCollateralLong()
            // );

            // console.log("liquidity %s", hook.liquidity());
            // console.log("liquidityCheck %s", liquidityCheck);

            // assertApproxEqAbs(hook.liquidity(), (liquidityCheck * liquidityMultiplier) / 1e18, 1);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 10000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);

            // uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            // (uint256 deltaX, uint256 deltaY) = _checkSwap(
            //     hook.liquidity(),
            //     uint160(preSqrtPrice),
            //     uint160(postSqrtPrice)
            // );
            // assertApproxEqAbs(deltaETH, deltaY, 2);
            // assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 2);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

        // ** Deposit
        {
            uint256 _amountToDep = 200 ether;
            deal(address(WETH), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            alm.deposit(alice.addr, _amountToDep, 0);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 5000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);

            // uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            // (uint256 deltaX, uint256 deltaY) = _checkSwap(
            //     hook.liquidity(),
            //     uint160(preSqrtPrice),
            //     uint160(postSqrtPrice)
            // );
            // assertApproxEqAbs(deltaETH, deltaY, 1);
            // assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 2);
        }

        // ** Swap Up out
        {
            uint256 ethToGetFSwap = 1e17;
            uint256 usdcToSwapQ = quoteUSDC_ETH_Out(ethToGetFSwap);
            console.log("usdcToSwapQ %s", usdcToSwapQ);

            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_Out(ethToGetFSwap);
            // uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            // (uint256 deltaX, uint256 deltaY) = _checkSwap(
            //     hook.liquidity(),
            //     uint160(preSqrtPrice),
            //     uint160(postSqrtPrice)
            // );

            // assertApproxEqAbs(deltaETH, deltaY, 1);
            // assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 5);
        }

        // ** Swap Down In
        {
            uint256 ethToSwap = 10e18;
            deal(address(swapper.addr), ethToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapETH_USDC_In(ethToSwap);
            // uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            // (uint256 deltaX, uint256 deltaY) = _checkSwap(
            //     hook.liquidity(),
            //     uint160(preSqrtPrice),
            //     uint160(postSqrtPrice)
            // );
            // assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 3);
            // assertApproxEqAbs(deltaUSDC, deltaX, 2);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

        // ** Rebalance
        {
            uint256 preRebalanceTVL = calcTVL();
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);
            // assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
            // assertEqBalanceStateZero(address(hook));
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

        // ** Full withdraw
        {
            setProtocolStatus(2);
            uint256 sharesToWithdraw = alm.balanceOf(alice.addr);
            vm.prank(alice.addr);
            alm.withdraw(alice.addr, sharesToWithdraw, 0, 0);
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
