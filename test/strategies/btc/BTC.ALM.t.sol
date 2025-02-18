// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// ** v4 imports
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";

// ** libraries
import {TokenWrapperLib as TW} from "@src/libraries/TokenWrapperLib.sol";
import {TestLib} from "@test/libraries/TestLib.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

contract BTCALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16;
    uint256 slippage = 50e14;
    uint256 fee = 5e14;

    TestERC20 BTC = TestERC20(TestLib.cbBTC);
    TestERC20 USDC = TestERC20(TestLib.USDC);

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
        console.log("v3Pool: initialPrice %s", getV3PoolPrice(TARGET_SWAP_POOL));
        console.log("v3Pool: initialSQRTPrice %s", initialSQRTPrice);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.cbBTC, 8, "BTC");
        create_lending_adapter(
            TestLib.eulerUSDCVault1,
            2000000e6,
            TestLib.eulerCbBTCVault1,
            0,
            TestLib.eulerUSDCVault2,
            0,
            TestLib.eulerCbBTCVault2,
            100e8
        );
        create_oracle(TestLib.chainlink_feed_cbBTC, TestLib.chainlink_feed_USDC);
        console.log("oracle: initialPrice %s", oracle.price());
        init_hook(true);
        assertEq(hook.tickLower(), -65897);
        assertEq(hook.tickUpper(), -71897);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setIsInvertAssets(false);
            // hook.setIsInvertedPool(?); // @Notice: this is already set in the init_hook, cause it's needed on initialize
            hook.setSwapPriceThreshold(48808848170151600); //(sqrt(1.1)-1) or max 10% price change
            rebalanceAdapter.setIsInvertAssets(false);
            positionManager.setFees(0);
            positionManager.setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalancePriceThreshold(1e15);
            rebalanceAdapter.setRebalanceTimeThreshold(2000);
            rebalanceAdapter.setWeight(weight);
            rebalanceAdapter.setLongLeverage(longLeverage);
            rebalanceAdapter.setShortLeverage(shortLeverage);
            rebalanceAdapter.setMaxDeviationLong(1e17); // 0.1 (1%)
            rebalanceAdapter.setMaxDeviationShort(1e17); // 0.1 (1%)
            vm.stopPrank();
        }
        approve_accounts();
    }

    uint256 amountToDep = 10 * 1e8;

    function test_deposit() public {
        assertEq(hook.TVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(BTC), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        (, uint256 shares) = hook.deposit(alice.addr, amountToDep);
        console.log("shares %s", shares);

        assertApproxEqAbs(shares, 9999999990000000000, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(hook.TVL(), 9999999990000000000, 1e1, "tvl");
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        test_deposit();

        uint256 preRebalanceTVL = hook.TVL();

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage * 10);
        assertEqBalanceStateZero(address(hook));
        // assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage); //TODO: Y, error is here
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);

        positionManager.setFees(fee);
        rebalanceAdapter.setRebalancePriceThreshold(1e15);
        rebalanceAdapter.setRebalanceTimeThreshold(60 * 60 * 24 * 7);

        vm.stopPrank();
        test_deposit_rebalance();

        //     // ** Make oracle change with swap price
        //     alignOraclesAndPools(hook.sqrtPriceCurrent());

        //     // ** Swap Up In
        //     {
        //         console.log("Swap Up In");
        //         uint256 usdcToSwap = 100000e6; // 100k USDC
        //         deal(address(USDC), address(swapper.addr), usdcToSwap);

        //         uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //         (, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

        //         uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //         (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //             uint256(hook.liquidity()) / 1e12,
        //             uint160(preSqrtPrice),
        //             uint160(postSqrtPrice)
        //         );
        //         assertApproxEqAbs(deltaBTC, deltaX, 1e15);
        //         assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        //     }

        //     // ** Swap Up In
        //     {
        //         console.log("Swap Up In");
        //         uint256 usdcToSwap = 5000e6; // 5k USDC
        //         deal(address(USDC), address(swapper.addr), usdcToSwap);

        //         uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //         (, uint256 deltaBTC) = swapUSDC_BTC_IN(usdcToSwap);

        //         uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //         (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //             uint256(hook.liquidity()) / 1e12,
        //             uint160(preSqrtPrice),
        //             uint160(postSqrtPrice)
        //         );
        //         assertApproxEqAbs(deltaBTC, deltaX, 1e15);
        //         assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        //     }

        //     // ** Swap Down Out
        //     {
        //         console.log("Swap Down Out");
        //         uint256 usdcToGetFSwap = 100000e6; //100k USDC
        //         (, uint256 btcToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        //         deal(address(BTC), address(swapper.addr), btcToSwapQ);

        //         uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //         (uint256 deltaUSDC, uint256 deltaBTC) = swapBTC_USDC_Out(usdcToGetFSwap);

        //         uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //         (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //             uint256(hook.liquidity()) / 1e12,
        //             uint160(preSqrtPrice),
        //             uint160(postSqrtPrice)
        //         );
        //         assertApproxEqAbs(deltaBTC, (deltaX * (1e18 + fee)) / 1e18, 7e14);
        //         assertApproxEqAbs(deltaUSDC, deltaY, 2e6);
        //     }

        //     // ** Make oracle change with swap price
        //     alignOraclesAndPools(hook.sqrtPriceCurrent());

        //     // ** Withdraw
        //     {
        //         uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        //         vm.prank(alice.addr);
        //         hook.withdraw(alice.addr, sharesToWithdraw / 2, 0);
        //     }

        //     // ** Make oracle change with swap price
        //     alignOraclesAndPools(hook.sqrtPriceCurrent());

        //     // ** Deposit
        //     {
        //         uint256 _amountToDep = 200 ether;
        //         deal(address(BTC), address(alice.addr), _amountToDep);
        //         vm.prank(alice.addr);
        //         hook.deposit(alice.addr, _amountToDep);
        //     }

        //     // ** Swap Up In
        //     {
        //         console.log("Swap Up In");
        //         uint256 usdcToSwap = 10000e6; // 10k USDC
        //         deal(address(USDC), address(swapper.addr), usdcToSwap);

        //         uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //         (, uint256 deltaBTC) = swapUSDC_BTC_In(usdcToSwap);

        //         uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //         (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //             uint256(hook.liquidity()) / 1e12,
        //             uint160(preSqrtPrice),
        //             uint160(postSqrtPrice)
        //         );
        //         assertApproxEqAbs(deltaBTC, deltaX, 1e15);
        //         assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        //     }

        //     // ** Swap Up out
        //     {
        //         console.log("Swap Up Out");
        //         uint256 btcToGetFSwap = 5e18;
        //         (uint256 usdcToSwapQ, uint256 ethToSwapQ) = hook.quoteSwap(true, int256(btcToGetFSwap));
        //         deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        //         uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //         (uint256 deltaUSDC, uint256 deltaBTC) = swapUSDC_BTC_Out(btcToGetFSwap);
        //         uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //         (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //             uint256(hook.liquidity()) / 1e12,
        //             uint160(preSqrtPrice),
        //             uint160(postSqrtPrice)
        //         );
        //         assertApproxEqAbs(deltaBTC, deltaX, 3e14);
        //         assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 + fee)) / 1e18, 1e7);
        //     }

        //     // ** Swap Down In
        //     {
        //         console.log("Swap Down In");
        //         uint256 btcToSwap = 10e18;
        //         deal(address(BTC), address(swapper.addr), btcToSwap);

        //         uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //         (uint256 deltaUSDC, uint256 deltaBTC) = swapBTC_USDC_In(btcToSwap);
        //         uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //         (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //             uint256(hook.liquidity()) / 1e12,
        //             uint160(preSqrtPrice),
        //             uint160(postSqrtPrice)
        //         );
        //         // assertApproxEqAbs(deltaBTC, (deltaX * (1e18 + fee)) / 1e18, 4e14); //TODO: Y, error is here
        //         // assertApproxEqAbs(deltaUSDC, deltaY, 1e7); //TODO: Y, error is here
        //     }

        //     // ** Make oracle change with swap price
        //     alignOraclesAndPools(hook.sqrtPriceCurrent());

        //     // ** Rebalance
        //     uint256 preRebalanceTVL = hook.TVL();
        //     vm.prank(deployer.addr);
        //     rebalanceAdapter.rebalance(slippage);
        //     assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        //     // ** Make oracle change with swap price
        //     alignOraclesAndPools(hook.sqrtPriceCurrent());

        //     // ** Full withdraw
        //     {
        //         uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        //         vm.prank(alice.addr);
        //         hook.withdraw(alice.addr, sharesToWithdraw, 0);
        //     }
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
