// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {TokenWrapperLib as TW} from "@src/libraries/TokenWrapperLib.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** interfaces
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// This test illustrates the pool with the reversed order of currencies. The main asset first and the stable next.
contract ETHRALMTest is ALMTestBase {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16; //50%
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 15e14; //0.15%
    uint256 fee = 5e14; //0.05%

    uint256 k1 = 1425e15; //1.425
    uint256 k2 = 1425e15; //1.425

    IERC20 WETH = IERC20(TestLib.WETH);
    IERC20 USDT = IERC20(TestLib.USDT);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_WETH_USDT_POOL;
            assertEqPSThresholdCL = 1e1;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e1;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDT, 6, "USDT", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler(TestLib.eulerUSDTVault1, 3000000 * 1e6, TestLib.eulerWETHVault1, 0);
        create_flash_loan_adapter_euler(TestLib.eulerUSDTVault2, 3000000 * 1e6, TestLib.eulerWETHVault2, 0);
        create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDT, 1 hours, 10 hours);
        init_hook(false, false, false, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per_price_change);
        assertEq(hook.tickLower(), -200488);
        assertEq(hook.tickUpper(), -194488);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            IPositionManagerStandard(address(positionManager)).setFees(0);
            IPositionManagerStandard(address(positionManager)).setKParams(k1, k2);
            rebalanceAdapter.setRebalanceParams(weight, liquidityMultiplier, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(1e15, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();
    }

    uint256 amountToDep = 100 ether;

    function test_deposit() public {
        assertEq(hook.TVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, amountToDep, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(hook.TVL(), amountToDep, 1e1, "tvl");
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        test_deposit();
        uint256 preRebalanceTVL = hook.TVL();

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);

        IPositionManagerStandard(address(positionManager)).setFees(fee);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)

        vm.stopPrank();
        test_deposit_rebalance();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        vm.startPrank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);
        hook.setProtocolParams(
            20 * 1e16, // 20% from fees
            hook.tvlCap(),
            hook.tickUpperDelta(),
            hook.tickLowerDelta(),
            hook.swapPriceThreshold()
        );
        vm.stopPrank();

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

            uint256 usdtToSwap = 10e9; // 10k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);

            (uint256 deltaWETH, ) = swapUSDT_WETH_In(usdtToSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaWETH, (deltaY * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdtToSwap, deltaX, 1);

            uint256 deltaTreasuryFee = (deltaY * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);
            assertEqPositionState(
                CL - ((deltaWETH + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdtToSwap,
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

            uint256 usdtToSwap = 20e9; // 20k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);
            (uint256 deltaWETH, ) = swapUSDT_WETH_In(usdtToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(usdtToSwap, deltaX, 1);
            assertApproxEqAbs(deltaWETH, (deltaY * (1e18 - fee)) / 1e18, 1);

            uint256 deltaTreasuryFee = (deltaY * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);
            assertEqPositionState(
                CL - ((deltaWETH + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdtToSwap,
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

            uint256 usdtToGetFSwap = 20000e6; //20k USDT
            (uint256 wethToSwapQ, ) = hook.quoteSwap(true, int256(usdtToGetFSwap));

            deal(address(WETH), address(swapper.addr), wethToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWETH, uint256 deltaUSDT) = swapWETH_USDT_Out(usdtToGetFSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaUSDT, deltaX, 1);
            assertApproxEqAbs(deltaWETH, (deltaY * (1e18 + fee)) / 1e18, 1);

            uint256 deltaTreasuryFee = (deltaY * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);
            assertEqPositionState(
                CL + ((deltaWETH - deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) + deltaUSDT,
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

        // ** Swap Up In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdtToSwap = 20e9;
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);
            (uint256 deltaWETH, ) = swapUSDT_WETH_In(usdtToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(usdtToSwap, deltaX, 1);
            assertApproxEqAbs(deltaWETH, (deltaY * (1e18 - fee)) / 1e18, 1);

            uint256 deltaTreasuryFee = (deltaY * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                CL - ((deltaWETH + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdtToSwap,
                DS - ((k1 - 1e18) * (deltaWETH + deltaTreasuryFee)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

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

            uint256 usdtToSwap = 4e9;
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);
            (uint256 deltaWETH, ) = swapUSDT_WETH_In(usdtToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(usdtToSwap, deltaX, 1);
            assertApproxEqAbs(deltaWETH, (deltaY * (1e18 - fee)) / 1e18, 1);

            uint256 deltaTreasuryFee = (deltaY * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 3, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                CL - ((deltaWETH + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdtToSwap,
                DS - ((k1 - 1e18) * (deltaWETH + deltaTreasuryFee)) / 1e18
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

            uint256 wethToGetFSwap = 1e18;
            (, uint256 usdtToSwapQ) = hook.quoteSwap(false, int256(wethToGetFSwap));
            deal(address(USDT), address(swapper.addr), usdtToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWETH, uint256 deltaUSDT) = swapUSDT_WETH_Out(wethToGetFSwap);
            console.log("SWAP DONE");
            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(hook.sqrtPriceCurrent())
            );

            assertApproxEqAbs(deltaUSDT, (deltaX * (1e18 + fee)) / 1e18, 1);
            assertApproxEqAbs(deltaWETH, deltaY, 1e5); //rounding direction
            uint256 deltaTreasuryFeeB = (deltaX * fee * hook.protocolFee()) / 1e36;

            // treasuryFeeB += deltaTreasuryFee;

            assertApproxEqAbs(hook.accumulatedFeeB(), deltaTreasuryFeeB, 3, "treasuryFee");
            assertEqBalanceState(address(hook), treasuryFeeQ, deltaTreasuryFeeB);

            console.log("deltaTreasuryFeeB %s", deltaTreasuryFeeB);

            assertEqPositionState(
                CL - ((deltaWETH) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - deltaUSDT + deltaTreasuryFeeB,
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

            console.log("CL %s", CL);
            console.log("DL %s", DL);

            uint256 wethToSwap = 10e18;
            deal(address(WETH), address(swapper.addr), wethToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWETH, uint256 deltaUSDT) = swapWETH_USDT_In(wethToSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaUSDT, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(deltaWETH, deltaY, 1e5); //rounding direction
            console.log("deltaWETH %s", deltaWETH);
            console.log("deltaY %s", deltaY);

            uint256 deltaTreasuryFeeB = (deltaX * fee * hook.protocolFee()) / 1e36;

            // treasuryFeeB += deltaTreasuryFeeB;
            console.log("treasuryFeeB %s", hook.accumulatedFeeB());
            console.log("deltaTreasuryFeeB %s", deltaTreasuryFeeB);

            // assertApproxEqAbs(hook.accumulatedFeeB(), deltaTreasuryFeeB, 3, "treasuryFee");
            // assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            // console.log("deltaTreasuryFeeQ %s", treasuryFeeB);

            assertEqPositionState(
                CL + (deltaWETH * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) + deltaUSDT + deltaTreasuryFeeB,
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
        // assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage); //TODO check after all the cases on slippage

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
    function swapWETH_USDT_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, int256(amount), key);
    }

    function swapWETH_USDT_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, -int256(amount), key);
    }

    function swapUSDT_WETH_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, int256(amount), key);
    }

    function swapUSDT_WETH_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }
}
