// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";

// ** contracts
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenWrapperLib as TW} from "@src/libraries/TokenWrapperLib.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {ALMMathLib} from "../../../src/libraries/ALMMathLib.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IFlashLoanAdapter} from "@src/interfaces/IFlashLoanAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {ISwapAdapter} from "@src/interfaces/swapAdapters/ISwapAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";

contract ETHALMTest is MorphoTestBase {
    using SafeERC20 for IERC20;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16; //50%
    uint256 liquidityMultiplier = 2e18;
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
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        create_flash_loan_adapter_euler_WETH_USDC();
        create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC, 1 hours, 10 hours);
        init_hook(true, false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);
        assertTicks(200466, 194466);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            IPositionManagerStandard(address(positionManager)).setFees(0);
            IPositionManagerStandard(address(positionManager)).setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(1e15, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();
    }

    function test_withdraw() public {
        vm.expectRevert(IALM.NotZeroShares.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 0, 0, 0);

        vm.expectRevert();
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 10, 0, 0);
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

    function test_deposit_cap() public {
        vm.startPrank(deployer.addr);
        updateProtocolTVLCap(10 ether);
        vm.stopPrank();

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        vm.expectRevert(IALM.TVLCapExceeded.selector);
        hook.deposit(alice.addr, amountToDep, 0);
    }

    function test_deposit_min_shares() public {
        assertEq(hook.TVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        vm.expectRevert(IALM.NotMinShares.selector);
        hook.deposit(alice.addr, amountToDep, type(uint256).max / 2);
    }

    function test_deposit_not_operator() public {
        vm.prank(deployer.addr);
        hook.setOperators(deployer.addr, deployer.addr);
        deal(address(WETH), address(alice.addr), amountToDep);

        vm.prank(alice.addr);
        vm.expectRevert(IALM.NotALiquidityOperator.selector);
        hook.deposit(alice.addr, amountToDep, 0);

        vm.prank(deployer.addr);
        hook.setOperators(alice.addr, deployer.addr);

        vm.prank(alice.addr);
        hook.deposit(alice.addr, amountToDep, 0);
    }

    function test_deposit_rebalance() public {
        test_deposit();

        uint256 preRebalanceTVL = hook.TVL();

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        console.log("liquidity %s", hook.liquidity());
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        uint128 liquidityCheck = LiquidityAmounts.getLiquidityForAmount1(
            ALMMathLib.getSqrtPriceX96FromTick(tickLower),
            ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
            TW.unwrap(lendingAdapter.getCollateralLong(), qDec)
        );

        assertApproxEqAbs(hook.liquidity(), (liquidityCheck * liquidityMultiplier) / 1e18, 1);
    }

    function test_deposit_rebalance_revert_no_rebalance_needed() public {
        test_deposit_rebalance();

        vm.expectRevert(SRebalanceAdapter.RebalanceConditionNotMet.selector);
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
    }

    function test_deposit_rebalance_revert_not_rebalance_operator() public {
        test_deposit_rebalance();

        vm.expectRevert(SRebalanceAdapter.NotRebalanceOperator.selector);
        vm.prank(alice.addr);
        rebalanceAdapter.rebalance(slippage);
    }

    function test_deposit_rebalance_withdraw() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());
        part_withdraw();
    }

    function test_deposit_rebalance_withdraw_not_operator() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        vm.prank(deployer.addr);
        hook.setOperators(deployer.addr, deployer.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        vm.expectRevert(IALM.NotALiquidityOperator.selector);
        hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);

        vm.prank(deployer.addr);
        hook.setOperators(alice.addr, deployer.addr);

        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
    }

    // @Notice: this is needed for composability testing
    function part_withdraw() public {
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        assertEq(hook.balanceOf(alice.addr), 0);

        assertEqBalanceState(alice.addr, 99980051006901010606, 0);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(hook.TVL(), 0, 1e4, "tvl");
        assertEqBalanceStateZero(address(hook));
    }

    function test_deposit_rebalance_withdraw_on_shutdown() public {
        test_deposit_rebalance();

        alignOraclesAndPools(hook.sqrtPriceCurrent());

        vm.prank(deployer.addr);
        hook.setStatus(2);

        part_withdraw();
    }

    function test_deposit_rebalance_withdraw_revert_min_out() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.expectRevert(IALM.NotMinOutWithdrawQuote.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0, type(uint256).max);
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        test_deposit_rebalance();
        part_swap_price_up_in();
    }

    // @Notice: this is needed for composability testing
    function part_swap_price_up_in() public {
        uint256 usdcToSwap = 14541602182;

        console.log("preCL %s", lendingAdapter.getCollateralLong());
        console.log("preCS %s", lendingAdapter.getCollateralShort());
        console.log("preDL %s", lendingAdapter.getBorrowedLong());
        console.log("preDS %s", lendingAdapter.getBorrowedShort());

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5439224791342722064, 1e4, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249104672336621054, 239418121556, 277892039995, 42755829463679343123);

        assertEq(hook.sqrtPriceCurrent(), 1528486427985910873144190591580871);
        assertApproxEqAbs(hook.TVL(), 100030490867261280905, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        console.log("preCL %s", lendingAdapter.getCollateralLong());
        console.log("preCS %s", lendingAdapter.getCollateralShort());
        console.log("preDL %s", lendingAdapter.getBorrowedLong());
        console.log("preDS %s", lendingAdapter.getBorrowedShort());

        uint256 wethToGetFSwap = 5438946754462608168;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertApproxEqAbs(usdcToSwapQ, 14540855151, 1e4, "deltaUSDCQuote");

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5438946754462608168, 1e1, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249500874890783357, 239418121556, 277892787026, 42755947629353391529);

        assertEq(hook.sqrtPriceCurrent(), 1528486817682343993160199836892981);
        assertApproxEqAbs(hook.TVL(), 100030488086676273144, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_not_operator() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 5438946754462608168;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertApproxEqAbs(usdcToSwapQ, 14540855151, 1e4, "deltaUSDCQuote");
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        vm.prank(deployer.addr);
        hook.setOperators(deployer.addr, deployer.addr);

        part_swap_USDC_WETH_OUT_revert(wethToGetFSwap);

        vm.prank(deployer.addr);
        hook.setOperators(deployer.addr, address(swapRouter));

        swapUSDC_WETH_Out(wethToGetFSwap);
    }

    function test_deposit_rebalance_swap_price_up_out_revert_deviations() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 100e18;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        part_swap_USDC_WETH_OUT_revert(wethToGetFSwap);
    }

    function part_swap_USDC_WETH_OUT_revert(uint256 amount) internal {
        bool hasReverted = false;
        try this.swapUSDC_WETH_Out(amount) {
            hasReverted = false;
        } catch {
            hasReverted = true;
            vm.stopPrank();
        }
        assertTrue(hasReverted, "Expected function to revert but it didn't");
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        uint256 wethToSwap = 5521148324215010000;
        test_deposit_rebalance();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14613746759);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172867636362006389246, 239418121556, 307047388936, 47413988037791379250);

        assertEq(hook.sqrtPriceCurrent(), 1543848484656406112881723444165282);
        assertApproxEqAbs(hook.TVL(), 100031036098368390523, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        uint256 usdcToGetFSwap = 14614493789;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5521431977802295446);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172868040568368271007, 239418121556, 307048135966, 47414108590565975565);

        assertEq(hook.sqrtPriceCurrent(), 1543848882225214831905187600369497);
        assertApproxEqAbs(hook.TVL(), 100031038934866465706, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);

        uint256 usdcToSwap = 14541602182;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5436505178947050703, 1e4, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
        console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

        assertEqPositionState(157252980120000452744, 239418121556, 277892039995, 42756985298947503451);

        assertEq(hook.sqrtPriceCurrent(), 1528486427985910873144190591580871);
        assertApproxEqAbs(hook.TVL(), 100033210479656952267, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);

        uint256 wethToGetFSwap = 5438946754462608168;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 14548125579); //prev case + fee (tokenIn + fee)
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5438946754462608168, 1e1, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249500874890783357, 239418121556, 277885516598, 42755947629353391529);

        assertEq(hook.sqrtPriceCurrent(), 1528486817682343993160199836892981);
        assertApproxEqAbs(hook.TVL(), 100033221123406086934, 1e1, "TVL");
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        uint256 wethToSwap = 5521148324215010000;
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14606439886); //less usdc to receive

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172867636362006389246, 239418121556, 307040082063, 47413988037791379250);

        assertEq(hook.sqrtPriceCurrent(), 1543848484656406112881723444165282);
        assertApproxEqAbs(hook.TVL(), 100033782835188985496, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);

        uint256 usdcToGetFSwap = 14614493789;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5524192693791196594);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172871974588652455142, 239418121556, 307048135966, 47415281894861258552);

        assertEq(hook.sqrtPriceCurrent(), 1543848882225214831905187600369497);
        assertApproxEqAbs(hook.TVL(), 100033799650855366854, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_in_protocol_fees() public {
        test_deposit_rebalance();

        vm.startPrank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);
        updateProtocolFees(20 * 1e16); // 20% cut from trading fees
        vm.stopPrank();

        assertEqBalanceState(address(hook), 0, 0);
        assertEq(hook.accumulatedFeeB(), 0);

        uint256 usdcToSwap = 14541602182;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5436505178947050703, 1e4, "deltaWETH");

        console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
        console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 543922479134272, 0);
        assertEq(hook.accumulatedFeeQ(), 543922479134272);

        assertEqPositionState(157252205030467686407, 239418121556, 277892039995, 42756754131893871386);

        assertEq(hook.sqrtPriceCurrent(), 1528486427985910873144190591580871);
        assertApproxEqAbs(hook.TVL(), 100032666557177817995, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_protocol_fees() public {
        test_deposit_rebalance();
        vm.startPrank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        uint256 wethToGetFSwap = 5438946754462608168;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 14548125579);
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5438946754462608168, 1e1, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 1454086);
        assertEq(hook.accumulatedFeeB(), 1454086);

        assertEqPositionState(157249500874890783357, 239418121556, 277886970684, 42755947629353391529);

        assertEq(hook.sqrtPriceCurrent(), 1528486817682343993160199836892981);
        assertApproxEqAbs(hook.TVL(), 100032674515909759618, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_in_protocol_fees() public {
        uint256 wethToSwap = 5521148324215010000;
        test_deposit_rebalance();

        vm.startPrank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14606439886);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 1461375);
        assertEq(hook.accumulatedFeeB(), 1461375);

        assertEqPositionState(172867636362006389246, 239418121556, 307041543438, 47413988037791379250);

        assertEq(hook.sqrtPriceCurrent(), 1543848484656406112881723444165282);
        assertApproxEqAbs(hook.TVL(), 100033233487674501944, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out_protocol_fees() public {
        test_deposit_rebalance();
        vm.startPrank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(5 * 1e14);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        console.log("preCL %s", lendingAdapter.getCollateralLong());
        console.log("preCS %s", lendingAdapter.getCollateralShort());
        console.log("preDL %s", lendingAdapter.getBorrowedLong());
        console.log("preDS %s", lendingAdapter.getBorrowedShort());

        uint256 usdcToGetFSwap = 14614493789;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5524192693791196594);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 552143197780230, 0);
        assertEq(hook.accumulatedFeeQ(), 552143197780230);

        assertEqPositionState(172871187784595618314, 239418121556, 307048135966, 47415047234002201955);

        assertEq(hook.sqrtPriceCurrent(), 1543848882225214831905187600369497);
        assertApproxEqAbs(hook.TVL(), 100033247507657586623, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_rebalance() public {
        test_deposit_rebalance_swap_price_up_in();

        // ** Fail swap without oracle update
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.RebalanceConditionNotMet.selector);
        rebalanceAdapter.rebalance(slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Second rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);

            assertEqBalanceStateZero(address(hook));
            assertEqPositionState(165286589149515387341, 242232369118, 295730297289, 45145777918156271025);
            assertApproxEqAbs(hook.TVL(), 100229449172237808546, 1e1, "tvl");
        }
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);

        IPositionManagerStandard(address(positionManager)).setFees(fee);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)

        vm.stopPrank();
        test_deposit_rebalance();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Swap Up In
        {
            uint256 usdcToSwap = 100000e6; // 100k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);
        }

        // ** Swap Down Out
        {
            uint256 usdcToGetFSwap = 200000e6; //200k USDC
            (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
            deal(address(WETH), address(swapper.addr), wethToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_Out(usdcToGetFSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 + fee)) / 1e18, 1);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 2, 0, 0);

            (int24 tickLower, int24 tickUpper) = hook.activeTicks();
            uint128 liquidityCheck = LiquidityAmounts.getLiquidityForAmount1(
                ALMMathLib.getSqrtPriceX96FromTick(tickLower),
                ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
                TW.unwrap(lendingAdapter.getCollateralLong(), qDec)
            );

            assertApproxEqAbs(hook.liquidity(), (liquidityCheck * liquidityMultiplier) / 1e18, 1);
            console.log("liquidity %s", hook.liquidity());
            console.log("liquidityCheck %s", liquidityCheck);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 50000e6; // 50k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);
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
            uint256 usdcToSwap = 10000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 - fee)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);
        }

        // ** Swap Up out
        {
            uint256 wethToGetFSwap = 5e18;
            (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 + fee)) / 1e18, 1);
        }

        // ** Swap Down In
        {
            uint256 wethToSwap = 10e18;
            deal(address(WETH), address(swapper.addr), wethToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_In(wethToSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 - fee)) / 1e18, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Rebalance
        uint256 preRebalanceTVL = hook.TVL();
        console.log("preRebalanceTVL %s", preRebalanceTVL);
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage * 2);
        //assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage); //TODO check after all the cases on slippage

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        }
    }

    function test_lending_adapter_migration() public {
        test_deposit_rebalance();

        uint256 CLbefore = lendingAdapter.getCollateralLong();
        uint256 CSbefore = lendingAdapter.getCollateralShort();
        uint256 DLbefore = lendingAdapter.getBorrowedLong();
        uint256 DSbefore = lendingAdapter.getBorrowedShort();

        // ** Create new lending adapter
        ILendingAdapter newAdapter;
        {
            vm.startPrank(deployer.addr);
            newAdapter = new EulerLendingAdapter(
                BASE,
                QUOTE,
                bDec,
                qDec,
                TestLib.EULER_VAULT_CONNECT,
                TestLib.eulerUSDCVault1,
                TestLib.eulerWETHVault1,
                TestLib.merklRewardsDistributor,
                TestLib.rEUL
            );
            IBase(address(newAdapter)).setComponents(
                hook,
                newAdapter,
                flashLoanAdapter,
                positionManager,
                oracle,
                IRebalanceAdapter(migrationContract.addr),
                swapAdapter
            );
        }

        // ** Withdraw collateral
        {
            IBase(address(lendingAdapter)).setComponents(
                hook,
                ILendingAdapter(migrationContract.addr),
                IFlashLoanAdapter(migrationContract.addr),
                IPositionManager(migrationContract.addr),
                IOracle(migrationContract.addr),
                IRebalanceAdapter(migrationContract.addr),
                ISwapAdapter(migrationContract.addr)
            );
            vm.stopPrank();

            // @Notice: This is like zero interest FL
            deal(address(USDC), migrationContract.addr, DLbefore);
            deal(address(WETH), migrationContract.addr, DSbefore);

            vm.startPrank(migrationContract.addr);
            USDC.forceApprove(address(lendingAdapter), type(uint256).max);
            WETH.forceApprove(address(lendingAdapter), type(uint256).max);

            lendingAdapter.repayLong(DLbefore);
            lendingAdapter.repayShort(DSbefore);

            lendingAdapter.removeCollateralLong(CLbefore);
            lendingAdapter.removeCollateralShort(CSbefore);
        }

        // ** Create the same position in the new lending adapter
        {
            USDC.forceApprove(address(newAdapter), type(uint256).max);
            WETH.forceApprove(address(newAdapter), type(uint256).max);

            newAdapter.addCollateralLong(CLbefore);
            newAdapter.addCollateralShort(CSbefore);
            newAdapter.borrowLong(DLbefore);
            newAdapter.borrowShort(DSbefore);

            // @Notice: Here we repay our FL
            USDC.safeTransfer(zero.addr, DLbefore);
            WETH.safeTransfer(zero.addr, DSbefore);
            vm.stopPrank();
        }

        // ** Connect all parts properly
        {
            vm.startPrank(deployer.addr);

            hook.setComponents(
                hook,
                newAdapter,
                flashLoanAdapter,
                positionManager,
                oracle,
                rebalanceAdapter,
                swapAdapter
            );

            IBase(address(newAdapter)).setComponents(
                hook,
                newAdapter,
                flashLoanAdapter,
                positionManager,
                oracle,
                rebalanceAdapter,
                swapAdapter
            );

            IBase(address(positionManager)).setComponents(
                hook,
                newAdapter,
                flashLoanAdapter,
                positionManager,
                oracle,
                rebalanceAdapter,
                swapAdapter
            );

            IBase(address(rebalanceAdapter)).setComponents(
                hook,
                newAdapter,
                flashLoanAdapter,
                positionManager,
                oracle,
                rebalanceAdapter,
                swapAdapter
            );
            vm.stopPrank();
        }

        assertEqBalanceStateZero(migrationContract.addr);

        // ** Check if states are the same
        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(164999999999999999995, 239418121555, 292433642177, 45067500000000000000);
        assertApproxEqAbs(hook.TVL(), 100003361700284165101, 1e1, "tvl");

        // ** Check if the same test case works for the new lending adapter
        //part_swap_price_up_in(); //TODO: fix
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
