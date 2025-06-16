// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    uint24 fee = 500; //0.05%
    uint256 testFee = 5e14; //just for tests

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
        create_oracle(true, TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC, 1 hours, 10 hours);
        init_hook(false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);
        assertTicks(194466, 200466);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            IPositionManagerStandard(address(positionManager)).setFees(0);
            IPositionManagerStandard(address(positionManager)).setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(TestLib.ONE_PERCENT_AND_ONE_BPS, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
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
        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(calcTVL(), amountToDep, 1e1, "tvl");
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
        assertEq(calcTVL(), 0, "TVL");
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

        uint256 preRebalanceTVL = calcTVL();

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        console.log("preRebalanceTVL %s", preRebalanceTVL);
        console.log("postRebalanceTVL %s", calcTVL());

        alignOraclesAndPools(hook.sqrtPriceCurrent());

        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        console.log("liquidity %s", hook.liquidity());
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        uint128 liquidityCheck = LiquidityAmounts.getLiquidityForAmount1(
            ALMMathLib.getSqrtPriceX96FromTick(tickLower),
            ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
            lendingAdapter.getCollateralLong()
        );

        assertApproxEqAbs(hook.liquidity(), (liquidityCheck * liquidityMultiplier) / 1e18, 1);
    }

    function test_only_rebalance() public {
        test_deposit_rebalance();
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

    /// @dev This is needed for composability testing.
    function part_withdraw() public {
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        assertEq(hook.balanceOf(alice.addr), 0);

        assertEqBalanceState(alice.addr, 99980051006901010606, 0);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(calcTVL(), 0, 1e4, "tvl");
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

    /// @dev This is needed for composability testing.
    function part_swap_price_up_in() public {
        uint256 usdcToSwap = 14541602182;

        console.log("preCL %s", lendingAdapter.getCollateralLong());
        console.log("preCS %s", lendingAdapter.getCollateralShort());
        console.log("preDL %s", lendingAdapter.getBorrowedLong());
        console.log("preDS %s", lendingAdapter.getBorrowedShort());

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5439224790608936570, 1e4, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249104673382265383, 239418121556, 277892039995, 42755829463991201958);

        assertEq(hook.sqrtPriceCurrent(), 1528486427985910860928397360202277);
        assertApproxEqAbs(calcTVL(), 100030490867261272191, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 5438946754462608168;
        (uint256 usdcToSwapQ, ) = _quoteSwap(true, int256(wethToGetFSwap));
        assertApproxEqAbs(usdcToSwapQ, 14540855151, 1e4, "deltaUSDCQuote");

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5438946754462608168, 1e1, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249500874890783357, 239418121556, 277892787026, 42755947629353391529);

        assertEq(hook.sqrtPriceCurrent(), 1528486817682343993160199836892980);
        assertApproxEqAbs(calcTVL(), 100030488087052184539, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_not_operator() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 5438946754462608168;
        (uint256 usdcToSwapQ, ) = _quoteSwap(true, int256(wethToGetFSwap));
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
        (uint256 usdcToSwapQ, ) = _quoteSwap(true, int256(wethToGetFSwap));
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

        console.log("preCS %s", lendingAdapter.getCollateralShort());
        console.log("preDL %s", lendingAdapter.getBorrowedLong());

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14613746761);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        console.log("postCS %s", lendingAdapter.getCollateralShort());
        console.log("postDL %s", lendingAdapter.getBorrowedLong());

        assertEqPositionState(172867636362006389246, 239418121589, 307047388971, 47413988037791379250);

        assertEq(hook.sqrtPriceCurrent(), 1543848484552533078340966435675234);
        assertApproxEqAbs(hook.TVL(), 100031036101054763958, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        uint256 wethToSwap = 5521148324215010000;
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(fee);

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14606476494);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172867636362006389246, 239418121589, 307040118704, 47413988037791379250);

        assertEq(hook.sqrtPriceCurrent(), 1543844615332363812012452971628599);
        assertApproxEqAbs(hook.TVL(), 100033769077262473583, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_in_protocol_fees() public {
        uint256 wethToSwap = 5521148324215010000;
        test_deposit_rebalance();

        vm.startPrank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(500);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14606476494);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 552114832421501, 0);
        assertEq(hook.accumulatedFeeQ(), 552114832421501);

        assertEqPositionState(172866849598370188606, 239418121589, 307040118704, 47413753388987600112);

        assertEq(hook.sqrtPriceCurrent(), 1543844615332363812012452971628599);
        assertApproxEqAbs(hook.TVL(), 100033216962430052081, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        uint256 usdcToGetFSwap = 14613746761;
        (, uint256 wethToSwapQ) = _quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5521148324187495351);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172868040567301490012, 239418121556, 307048135966, 47414108590247812812);

        assertEq(hook.sqrtPriceCurrent(), 1543848882225214835397928199912822);
        assertApproxEqAbs(calcTVL(), 100031038934866468198, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(500);

        uint256 usdcToSwap = 14541602182;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5436518669156719819, 1e4, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157252960896451674253, 239418121556, 277892039995, 42756979565608394077);

        assertEq(hook.sqrtPriceCurrent(), 1528490220886201798644076291683964);
        assertApproxEqAbs(calcTVL(), 100033196989447283150, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(500);

        uint256 wethToGetFSwap = 5438946754462608168;
        (uint256 usdcToSwapQ, ) = _quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 14548129217); //prev case + fee (tokenIn + fee)
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5438946754462608168, 1e1, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249500874890783357, 239418121556, 277885512960, 42755947629353391529);

        assertEq(hook.sqrtPriceCurrent(), 1528486817682343993160199836892980);
        assertApproxEqAbs(calcTVL(), 100033222490971740986, 1e1, "TVL");
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(50);

        uint256 usdcToGetFSwap = 14614493789;
        (, uint256 wethToSwapQ) = _quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5521708063205458212);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172868433990067777947, 239418121556, 307048135966, 47414225926862319740);

        assertEq(hook.sqrtPriceCurrent(), 1543848882225214835397928199912822);
        assertApproxEqAbs(calcTVL(), 100031315020269628471, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_in_protocol_fees() public {
        test_deposit_rebalance();

        vm.startPrank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(500);
        updateProtocolFees(20 * 1e16); // 20% cut from trading fees
        vm.stopPrank();

        assertEqBalanceState(address(hook), 0, 0);
        assertEq(hook.accumulatedFeeB(), 0);

        uint256 usdcToSwap = 14541602182;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5436518669156719819, 1e4, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 1454160);
        assertEq(hook.accumulatedFeeB(), 1454160);

        assertEqPositionState(157252960896451674253, 239418121556, 277893494155, 42756979565608394077);

        assertEq(hook.sqrtPriceCurrent(), 1528490220886201798644076291683964);
        assertApproxEqAbs(calcTVL(), 100032650354133512624, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_protocol_fees() public {
        test_deposit_rebalance();
        vm.startPrank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(500);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        uint256 wethToGetFSwap = 5438946754462608168;
        (uint256 usdcToSwapQ, ) = _quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 14548129217);
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5438946754462608168, 1e1, "deltaWETH");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 1454813);
        assertEq(hook.accumulatedFeeB(), 1454813);

        assertEqPositionState(157249500874890783357, 239418121556, 277886967773, 42755947629353391529);

        assertEq(hook.sqrtPriceCurrent(), 1528486817682343993160199836892980);
        assertApproxEqAbs(calcTVL(), 100032675610187829697, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out_protocol_fees() public {
        test_deposit_rebalance();
        vm.startPrank(deployer.addr);
        IPositionManagerStandard(address(positionManager)).setFees(50);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        uint256 usdcToGetFSwap = 14614493789;
        (, uint256 wethToSwapQ) = _quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 5521708063205458212);
        _quoteSwap(false, int256(usdcToGetFSwap));

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 55217080632055, 0);
        assertEq(hook.accumulatedFeeQ(), 55217080632055);

        assertEqPositionState(172868355305727877270, 239418121556, 307048135966, 47414202459603051117);

        assertEq(hook.sqrtPriceCurrent(), 1543848882225214835397928199912822);
        assertApproxEqAbs(calcTVL(), 100031259803188996417, 1e1, "tvl");
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
            assertApproxEqAbs(calcTVL(), 100229449172237798691, 1e1, "tvl");
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
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaWETH %s", deltaWETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 1);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaWETH %s", deltaWETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 1);
        }

        // ** Swap Down Out
        {
            uint256 usdcToGetFSwap = 200000e6; //200k USDC
            (, uint256 wethToSwapQ) = _quoteSwap(false, int256(usdcToGetFSwap));
            deal(address(WETH), address(swapper.addr), wethToSwapQ);
            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_Out(usdcToGetFSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaWETH %s", deltaWETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs((deltaWETH * (1e18 - testFee)) / 1e18, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Withdraw
        {
            console.log("liquidity %s", hook.liquidity());

            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 2, 0, 0);

            (int24 tickLower, int24 tickUpper) = hook.activeTicks();
            uint128 liquidityCheck = LiquidityAmounts.getLiquidityForAmount1(
                ALMMathLib.getSqrtPriceX96FromTick(tickLower),
                ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
                lendingAdapter.getCollateralLong()
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
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaWETH %s", deltaWETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 1);
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
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaWETH %s", deltaWETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs((usdcToSwap * (1e18 - testFee)) / 1e18, deltaY, 1);
        }

        // ** Swap Up out
        {
            uint256 wethToGetFSwap = 5e18;
            (uint256 usdcToSwapQ, ) = _quoteSwap(true, int256(wethToGetFSwap));
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaWETH %s", deltaWETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 1);
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

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaWETH %s", deltaWETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            assertApproxEqAbs((deltaWETH * (1e18 - testFee)) / 1e18, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Rebalance
        uint256 preRebalanceTVL = calcTVL();
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

            /// @dev This is like zero interest FL.
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

            // Here we repay our FL
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
        assertApproxEqAbs(calcTVL(), 100003361700284165101, 1e1, "tvl");

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
