// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {TokenWrapperLib as TW} from "@src/libraries/TokenWrapperLib.sol";

// ** interfaces
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BTCALMTest is ALMTestBase {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16;
    uint256 liquidityMultiplier = 1e18;
    uint256 slippage = 7e15;
    uint256 fee = 5e14;

    IERC20 BTC = IERC20(TestLib.cbBTC);
    IERC20 USDC = IERC20(TestLib.USDC);

    uint256 k1 = 1425e15; //1.425
    uint256 k2 = 1425e15; //1.425

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_cbBTC_USDC_POOL;
            assertEqPSThresholdCL = 1e2;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e2;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.cbBTC, 8, "BTC");
        create_lending_adapter_euler(TestLib.eulerUSDCVault1, 2000000e6, TestLib.eulerCbBTCVault1, 0);
        create_flash_loan_adapter_euler(TestLib.eulerUSDCVault2, 0, TestLib.eulerCbBTCVault2, 100e8);
        create_oracle(TestLib.chainlink_feed_cbBTC, TestLib.chainlink_feed_USDC, 10 hours, 10 hours);
        init_hook(true, false, false, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per_price_change);
        assertEq(hook.tickLower(), -65807);
        assertEq(hook.tickUpper(), -71807);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            IPositionManagerStandard(address(positionManager)).setFees(0);
            IPositionManagerStandard(address(positionManager)).setKParams(k1, k2); // 1.425 1.425
            rebalanceAdapter.setRebalanceParams(weight, liquidityMultiplier, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(1e15, 2000, 2e17, 2e17); // 0.2 (2%), 0.2 (2%)
            vm.stopPrank();
        }
        approve_accounts();
    }

    uint256 amountToDep = 1 * 1e8;

    function test_deposit() public {
        assertEq(hook.TVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(BTC), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, 999999990000000000, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(hook.TVL(), 999999990000000000, 1e1, "tvl");
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        test_deposit();

        uint256 preRebalanceTVL = hook.TVL();

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        // assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);

        hook.setProtocolParams(
            20 * 1e16, // 20% from fees
            hook.tvlCap(),
            hook.tickUpperDelta(),
            hook.tickLowerDelta(),
            hook.swapPriceThreshold()
        );
        IPositionManagerStandard(address(positionManager)).setFees(fee);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)

        vm.stopPrank();
        test_deposit_rebalance();

        uint256 treasuryFeeB;
        uint256 treasuryFeeQ;

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

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

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);
            (, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            console.log("deltaBTC %s", deltaBTC);
            console.log("deltaX - fee %s", (deltaX * (1e18 - fee)) / 1e18);

            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaBTC, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1e4); //rounding

            uint256 deltaTreasuryFee = (deltaX * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                TW.unwrap(CL, qDec) - ((deltaBTC + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdcToSwap,
                TW.unwrap(DS, qDec) - ((k1 - 1e18) * (deltaBTC + deltaTreasuryFee)) / 1e18
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

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);
            (, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaBTC, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1e4); //rounding

            uint256 deltaTreasuryFee = (deltaX * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 1, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                TW.unwrap(CL, qDec) - ((deltaBTC + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdcToSwap,
                TW.unwrap(DS, qDec) - ((k1 - 1e18) * (deltaBTC + deltaTreasuryFee)) / 1e18
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
            (, uint256 btcToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
            deal(address(BTC), address(swapper.addr), btcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapBTC_USDC_Out(usdcToGetFSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaBTC, (deltaX * (1e18 + fee)) / 1e18, 1);
            assertApproxEqAbs(deltaUSDC, deltaY, 1e4);

            uint256 deltaTreasuryFee = (deltaX * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                TW.unwrap(CL, qDec) + ((deltaBTC - deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) + deltaUSDC,
                TW.unwrap(DS, qDec) + ((k1 - 1e18) * (deltaBTC - deltaTreasuryFee)) / 1e18
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

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

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

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            console.log("preSqrtPrice %s", preSqrtPrice);
            (, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaBTC, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1e4); //rounding

            uint256 deltaTreasuryFee = (deltaX * fee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFee;
            assertEqBalanceState(address(hook), treasuryFeeQ, 0);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 10, "treasuryFee");

            console.log("treasuryFee %s", treasuryFeeQ);

            assertEqPositionState(
                TW.unwrap(CL, qDec) - ((deltaBTC + deltaTreasuryFee) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - usdcToSwap,
                TW.unwrap(DS, qDec) - ((k1 - 1e18) * (deltaBTC + deltaTreasuryFee)) / 1e18
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
            (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(btcToGetFSwap));
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_Out(btcToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(hook.sqrtPriceCurrent())
            );
            assertApproxEqAbs(deltaBTC, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 + fee)) / 1e18, 1);

            uint256 deltaTreasuryFeeB = (deltaY * fee * hook.protocolFee()) / 1e36;
            assertApproxEqAbs(hook.accumulatedFeeB(), deltaTreasuryFeeB, 3, "treasuryFee");

            assertEqPositionState(
                TW.unwrap(CL, qDec) - ((deltaBTC) * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) - deltaUSDC + deltaTreasuryFeeB,
                TW.unwrap(DS, qDec) - ((k1 - 1e18) * (deltaBTC)) / 1e18
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

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaBTC) = swapBTC_USDC_In(btcToSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            console.log("deltaX %s", deltaX);
            assertApproxEqAbs(deltaBTC, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 - fee)) / 1e18, 1);

            uint256 deltaTreasuryFeeB = (deltaY * fee * hook.protocolFee()) / 1e36;

            //treasuryFeeB += deltaTreasuryFeeB;
            console.log("treasuryFeeB %s", hook.accumulatedFeeB());
            console.log("deltaTreasuryFeeB %s", deltaTreasuryFeeB);

            //assertApproxEqAbs(hook.accumulatedFeeB(), deltaTreasuryFeeB, 3, "treasuryFee");
            //assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            //console.log("deltaTreasuryFeeQ %s", treasuryFeeB);

            assertEqPositionState(
                TW.unwrap(CL, qDec) + (deltaBTC * k1) / 1e18,
                TW.unwrap(CS, bDec),
                TW.unwrap(DL, bDec) + deltaUSDC + deltaTreasuryFeeB,
                TW.unwrap(DS, qDec) + ((k1 - 1e18) * (deltaBTC)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Rebalance
        uint256 preRebalanceTVL = hook.TVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        //assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

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
    function swapBTC_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, int256(amount), key);
    }

    function swapBTC_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }

    function swapUSDC_BTC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, int256(amount), key);
    }

    function swapUSDC_BTC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, -int256(amount), key);
    }
}
