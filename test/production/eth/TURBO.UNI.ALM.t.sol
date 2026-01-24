// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {LiquidityAmounts} from "v4-core-test/utils/LiquidityAmounts.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {TurboDeployConfig} from "@test/core/configs/TurboDeployConfig.sol";
import {DeployConfig} from "@test/core/configs/DeployConfig.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TURBO_UNI_ALMTest is ALMTestBaseUnichain {
    uint256 slippage = 5e14; //0.05%

    IERC20 USDT = IERC20(UConstants.USDT);
    IERC20 USDC = IERC20(UConstants.USDC);

    uint256 liquidityMultiplier;
    uint24 feeLP;

    function setUp() public {
        select_unichain_fork(38435153);
        DeployConfig.Config memory config = TurboDeployConfig.getConfig();

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
            IS_NTS = false;
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        manager = UConstants.manager;
        universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER;

        create_accounts_and_tokens(UConstants.USDC, 6, "USDC", UConstants.USDT, 6, "USDT");
        create_lending_adapter_euler_USDT_USDC_unichain();
        create_flash_loan_adapter_morpho_unichain();

        create_oracle(UConstants.chronicle_feed_USDC, UConstants.chronicle_feed_USDT, config.hookParams.isInvertedPool);
        mock_latestRoundData(UConstants.chronicle_feed_USDC, 999680000000000000);
        mock_latestRoundData(UConstants.chronicle_feed_USDT, 998660000000000000);

        liquidityMultiplier = config.hookParams.liquidityMultiplier;
        feeLP = config.hookParams.feeLP;
        feeLP = 5; // for this test
        init_hook(
            config.hookParams.isInvertedAssets,
            config.hookParams.isNova,
            liquidityMultiplier,
            config.hookParams.protocolFee,
            config.hookParams.tvlCap,
            config.hookParams.tickLowerDelta,
            config.hookParams.tickUpperDelta,
            config.hookParams.swapPriceThreshold
        );

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            positionManager.setKParams(config.kParams.k1, config.kParams.k2);
            rebalanceAdapter.setRebalanceParams(
                config.preDeployParams.weight,
                config.preDeployParams.longLeverage,
                config.preDeployParams.shortLeverage
            );
            rebalanceAdapter.setRebalanceConstraints(
                config.preDeployConstraints.rebalancePriceThreshold,
                config.preDeployConstraints.rebalanceTimeThreshold,
                config.preDeployConstraints.maxDeviationLong,
                config.preDeployConstraints.maxDeviationShort
            );
            vm.stopPrank();
        }

        approve_accounts();

        // Re-setup swap router for native-token
        {
            vm.startPrank(deployer.addr);
            uint8[4] memory swapConfig = [0, 2, 0, 2];
            setSwapAdapterToV4SingleSwap(USDC_USDT_key_unichain, swapConfig);
            vm.stopPrank();
        }
    }

    function test_setUp() public view {
        assertEq(alm.owner(), deployer.addr);
        assertTicks(-10, 10);
    }

    uint256 amountToDep = 10000e6;

    function test_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(USDT), address(alice.addr), amountToDep);
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

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        DeployConfig.Config memory config = TurboDeployConfig.getConfig();
        rebalanceAdapter.setRebalanceConstraints(
            config.preDeployConstraints.rebalancePriceThreshold,
            config.preDeployConstraints.rebalanceTimeThreshold,
            config.preDeployConstraints.maxDeviationLong,
            config.preDeployConstraints.maxDeviationShort
        );
        vm.stopPrank();

        test_deposit_rebalance();
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        saveBalance(address(manager));

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;

        // ** Swap Up In
        {
            uint256 usdcToSwap = 1000e6; // 1k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);

            return;
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaUSDT %s", deltaUSDT);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaUSDT, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 4);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 500e6; // 500 USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaUSDT, deltaX, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);
        }

        // ** Swap Down Out
        {
            uint256 usdcToGetFSwap = 1000e6; //1k USDC
            uint256 wethToSwapQ = quoteUSDT_USDC_Out(usdcToGetFSwap);

            deal(address(USDT), address(swapper.addr), wethToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDT_USDC_Out(usdcToGetFSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs((deltaUSDT * (1e18 - testFee)) / 1e18, deltaX, 2);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

        // ** Withdraw
        {
            uint256 sharesToWithdraw = alm.balanceOf(alice.addr);
            vm.prank(alice.addr);
            alm.withdraw(alice.addr, sharesToWithdraw / 2, 0, 0);

            (int24 tickLower, int24 tickUpper) = hook.activeTicks();
            uint128 liquidityCheck = LiquidityAmounts.getLiquidityForAmount1(
                ALMMathLib.getSqrtPriceX96FromTick(tickLower),
                ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
                lendingAdapter.getCollateralLong()
            );

            assertApproxEqAbs(hook.liquidity(), (liquidityCheck * liquidityMultiplier) / 1e18, 1);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 1000e6; // 1k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaUSDT, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

        // ** Deposit
        {
            uint256 _amountToDep = 5e9;
            deal(address(USDT), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            alm.deposit(alice.addr, _amountToDep, 0);
        }

        // ** Swap Up out
        {
            uint256 wethToGetFSwap = 690e6;
            uint256 usdcToSwapQ = quoteUSDC_USDT_Out(wethToGetFSwap);

            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDC_USDT_Out(wethToGetFSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaUSDT, deltaX, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 5);
        }

        // ** Swap Down In
        {
            uint256 wethToSwap = 420e6;
            deal(address(USDT), address(swapper.addr), wethToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDT_USDC_In(wethToSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs((deltaUSDT * (1e18 - testFee)) / 1e18, deltaX, 3);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

        // ** Rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);
            assertEqBalanceStateZero(address(hook));
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, USDC_USDT_key_unichain);

        // ** Full withdraw
        {
            setProtocolStatus(2);
            uint256 sharesToWithdraw = alm.balanceOf(alice.addr);
            vm.prank(alice.addr);
            alm.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        }

        assertBalanceNotChanged(address(manager), 2e1);
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
