// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// ** v4 imports
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UNICORDALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16; //50%
    uint256 slippage = 15e14; //0.15%
    uint256 fee = 5e14; //0.05%

    IERC20 WETH = IERC20(TestLib.WETH);
    IERC20 USDC = IERC20(TestLib.USDC);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_WETH_USDC_POOL;
            assertEqPSThresholdCL = 1e5;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e5;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        console.log("v3Pool: initialPrice %s", getV3PoolPrice(TARGET_SWAP_POOL));
        console.log("v3Pool: initialSQRTPrice %s", initialSQRTPrice);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter(
            TestLib.eulerUSDCVault1,
            0,
            TestLib.eulerWETHVault1,
            0,
            TestLib.eulerUSDCVault2,
            0,
            TestLib.eulerWETHVault2,
            0
        );
        create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC);
        console.log("oracle: initialPrice %s", oracle.price());
        init_hook(true);
        assertEq(hook.tickLower(), 200458);
        assertEq(hook.tickUpper(), 194458);

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
            rebalanceAdapter.setOraclePriceAtLastRebalance(2652e18);
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

        (, uint256 shares) = hook.deposit(alice.addr, amountToDep);
        console.log("shares %s", shares);

        assertApproxEqAbs(shares, amountToDep, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(hook.TVL(), amountToDep, 1e1, "tvl");
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    //TODO: this test should revert now it's just not reverting case we changed withdraw logic
    // function test_deposit_withdraw_revert() public {
    //     test_deposit();

    //     uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
    //     vm.expectRevert(IALM.ZeroDebt.selector);
    //     vm.prank(alice.addr);
    //     hook.withdraw(alice.addr, sharesToWithdraw, 0);
    // }

    function test_deposit_rebalance() public {
        test_deposit();

        uint256 preRebalanceTVL = hook.TVL();

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);

        positionManager.setFees(fee);
        rebalanceAdapter.setRebalancePriceThreshold(1e15);
        rebalanceAdapter.setRebalanceTimeThreshold(60 * 60 * 24 * 7);

        vm.stopPrank();
        test_deposit_rebalance();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Swap Up In
        {
            console.log("Swap Up In");
            console.log("Price before", getHookPrice());
            uint256 usdcToSwap = 100000e6; // 100k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            // uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            // (uint256 deltaX, uint256 deltaY) = _checkSwap(
            //     uint256(hook.liquidity()) / 1e12,
            //     uint160(preSqrtPrice),
            //     uint160(postSqrtPrice)
            // );
            // assertApproxEqAbs(deltaWETH, deltaX, 1e15);
            // assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
            console.log("Price after ", getHookPrice());
        }

        // // ** Swap Up In
        // {
        //     console.log("Swap Up In");
        //     uint256 usdcToSwap = 5000e6; // 5k USDC
        //     deal(address(USDC), address(swapper.addr), usdcToSwap);

        //     uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //     (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

        //     uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //     (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //         uint256(hook.liquidity()) / 1e12,
        //         uint160(preSqrtPrice),
        //         uint160(postSqrtPrice)
        //     );
        //     assertApproxEqAbs(deltaWETH, deltaX, 1e15);
        //     assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        // }

        // // ** Swap Down Out
        // {
        //     console.log("Swap Down Out");
        //     uint256 usdcToGetFSwap = 200000e6; //200k USDC
        //     (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        //     deal(address(WETH), address(swapper.addr), wethToSwapQ);

        //     uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //     (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_Out(usdcToGetFSwap);

        //     uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //     (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //         uint256(hook.liquidity()) / 1e12,
        //         uint160(preSqrtPrice),
        //         uint160(postSqrtPrice)
        //     );
        //     assertApproxEqAbs(deltaWETH, (deltaX * (1e18 + fee)) / 1e18, 9e14);
        //     assertApproxEqAbs(deltaUSDC, deltaY, 3e6);
        // }

        // // ** Make oracle change with swap price
        // alignOraclesAndPools(hook.sqrtPriceCurrent());

        // // ** Withdraw
        // {
        //     uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        //     vm.prank(alice.addr);
        //     hook.withdraw(alice.addr, sharesToWithdraw / 2, 0);
        // }

        // {
        //     console.log("Swap Up In");
        //     uint256 usdcToSwap = 50000e6; // 50k USDC
        //     deal(address(USDC), address(swapper.addr), usdcToSwap);

        //     uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //     (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

        //     uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //     (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //         uint256(hook.liquidity()) / 1e12,
        //         uint160(preSqrtPrice),
        //         uint160(postSqrtPrice)
        //     );
        //     assertApproxEqAbs(deltaWETH, deltaX, 1e15);
        //     assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        // }

        // // ** Make oracle change with swap price
        // alignOraclesAndPools(hook.sqrtPriceCurrent());

        // // ** Deposit
        // {
        //     uint256 _amountToDep = 200 ether;
        //     deal(address(WETH), address(alice.addr), _amountToDep);
        //     vm.prank(alice.addr);
        //     hook.deposit(alice.addr, _amountToDep);
        // }

        // // ** Swap Up In
        // {
        //     console.log("Swap Up In");
        //     uint256 usdcToSwap = 10000e6; // 10k USDC
        //     deal(address(USDC), address(swapper.addr), usdcToSwap);

        //     uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //     (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

        //     uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //     (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //         uint256(hook.liquidity()) / 1e12,
        //         uint160(preSqrtPrice),
        //         uint160(postSqrtPrice)
        //     );
        //     assertApproxEqAbs(deltaWETH, deltaX, 1e15);
        //     assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        // }

        // // ** Swap Up out
        // {
        //     console.log("Swap Up Out");
        //     uint256 wethToGetFSwap = 5e18;
        //     (uint256 usdcToSwapQ, uint256 ethToSwapQ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        //     deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        //     uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //     (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        //     uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //     (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //         uint256(hook.liquidity()) / 1e12,
        //         uint160(preSqrtPrice),
        //         uint160(postSqrtPrice)
        //     );
        //     assertApproxEqAbs(deltaWETH, deltaX, 3e14);
        //     assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 + fee)) / 1e18, 1e7);
        // }

        // // ** Swap Down In
        // {
        //     console.log("Swap Down In");
        //     uint256 wethToSwap = 10e18;
        //     deal(address(WETH), address(swapper.addr), wethToSwap);

        //     uint256 preSqrtPrice = hook.sqrtPriceCurrent();
        //     (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_In(wethToSwap);
        //     uint256 postSqrtPrice = hook.sqrtPriceCurrent();

        //     (uint256 deltaX, uint256 deltaY) = _checkSwap(
        //         uint256(hook.liquidity()) / 1e12,
        //         uint160(preSqrtPrice),
        //         uint160(postSqrtPrice)
        //     );
        //     assertApproxEqAbs((deltaWETH * (1e18 - fee)) / 1e18, deltaX, 42e13);
        //     assertApproxEqAbs(deltaUSDC, deltaY, 1e7);
        // }

        // // ** Make oracle change with swap price
        // alignOraclesAndPools(hook.sqrtPriceCurrent());

        // // ** Rebalance
        // uint256 preRebalanceTVL = hook.TVL();
        // vm.prank(deployer.addr);
        // rebalanceAdapter.rebalance(slippage);
        // assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        // // ** Make oracle change with swap price
        // alignOraclesAndPools(hook.sqrtPriceCurrent());

        // // ** Full withdraw
        // {
        //     uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        //     vm.prank(alice.addr);
        //     hook.withdraw(alice.addr, sharesToWithdraw, 0);
        // }
    }

    // ** Helpers
    function swapWETH_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, int256(amount), key);
    }

    function swapWETH_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }

    function swapUSDC_WETH_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, int256(amount), key);
    }

    function swapUSDC_WETH_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, -int256(amount), key);
    }
}
