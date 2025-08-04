// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiquidityAmounts} from "v4-core-test/utils/LiquidityAmounts.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

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

contract ETH_ALMTest is ALMTestBase {
    using SafeERC20 for IERC20;

    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16; //50%
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 15e14; //0.15%
    uint24 feeLP = 500; //0.05%

    IERC20 WETH = IERC20(MConstants.WETH);
    IERC20 USDC = IERC20(MConstants.USDC);

    function setUp() public {
        select_mainnet_fork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = MConstants.uniswap_v3_USDC_WETH_POOL;
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_euler_USDC_WETH();
        create_flash_loan_adapter_euler_USDC_WETH();
        create_oracle(true, MConstants.chainlink_feed_WETH, MConstants.chainlink_feed_USDC, 1 hours, 10 hours);
        init_hook(false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            // hook.setNextLPFee(0); // By default, dynamic-fee-pools initialize with a 0% fee, to change - call rebalance.
            IPositionManagerStandard(address(positionManager)).setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(TestLib.ONE_PERCENT_AND_ONE_BPS, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();
    }

    function test_setUp() public view {
        assertEq(hook.owner(), deployer.addr);
        assertTicks(194466, 200466);
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
        assertEqProtocolState(initialSQRTPrice, amountToDep);
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
        console.log("preRebalanceTVL %s", preRebalanceTVL);

        vm.expectRevert();
        rebalanceAdapter.rebalance(slippage);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        console.log("postRebalanceTVL %s", calcTVL());

        assertTicks(194458, 200458);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1536110044317873455854701961688542, 1e1, "sqrtPrice");

        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
        assertEq(hook.liquidity(), 56526950853149492, "liquidity");
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
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
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());
        part_withdraw();
    }

    function test_deposit_rebalance_withdraw_not_operator() public {
        test_deposit_rebalance();
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

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

        assertEqBalanceState(alice.addr, 99990323997909256072, 0);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(calcTVL(), 0, 1e4, "tvl");
        assertEqBalanceStateZero(address(hook));
    }

    function test_deposit_rebalance_withdraw_on_shutdown() public {
        test_deposit_rebalance();

        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        vm.prank(deployer.addr);
        hook.setStatus(2);

        part_withdraw();
    }

    function test_deposit_rebalance_withdraw_revert_min_out() public {
        test_deposit_rebalance();
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());
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
        // ** Before swap State
        uint256 usdcToSwap = 14541229590;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        uint160 preSqrtPrice = hook.sqrtPriceCurrent();
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5439086116224750588, 1e1, "deltaWETH");

        // ** After swap State
        _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(157249302284379730407, 239418121498, 277892412530, 42755888400416243368);

        assertApproxEqAbs(hook.TVL(oracle.price()), 100030489482569180703, 1e9); //1 wei drift on collateral supply
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1528486622352927269830375254242368, 1);
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();
        part_swap_price_up_out();
    }

    /// @dev This is needed for composability testing.
    function part_swap_price_up_out() internal {
        // ** Before swap State
        uint256 wethToGetFSwap = 5439086117469532134;
        uint256 usdcToSwapQ = quoteUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(usdcToSwapQ, 14541229590, 1e4, "deltaUSDCQuote");

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        uint160 preSqrtPrice = hook.sqrtPriceCurrent();
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5439086117469532134, 1e1, "deltaWETH");

        // ** After swap State
        (uint256 wethDelta, uint256 usdcDelta) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
        console.log("usdcDelta %s", usdcDelta);
        console.log("wethDelta %s", wethDelta);
        console.log("deltaWETH %s", deltaWETH);

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249302282605916703, 239418121498, 277892412530, 42755888399887211211);
        assertEqProtocolState(1528486622351182584276128648738257, 100030489482452133341);
    }

    function test_deposit_rebalance_swap_price_up_out_not_operator() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 wethToGetFSwap = 5438946754462608168;
        uint256 usdcToSwapQ = quoteUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(usdcToSwapQ, 14540855151, 1e4, "deltaUSDCQuote");
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        // ** Try Swap
        vm.prank(deployer.addr);
        hook.setOperators(deployer.addr, deployer.addr);
        part_swap_USDC_WETH_OUT_revert(wethToGetFSwap);

        // ** Swap
        vm.prank(deployer.addr);
        hook.setOperators(deployer.addr, address(swapRouter));
        swapUSDC_WETH_Out(wethToGetFSwap);
    }

    function test_deposit_rebalance_swap_price_up_out_revert_deviations() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 100e18;
        deal(address(USDC), address(swapper.addr), 1000000e6);

        // SwapPriceChangeTooHigh
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
        test_deposit_rebalance();

        // ** Before swap State
        uint256 wethToSwap = 5521289793622710000;
        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        // ** Swap
        uint160 preSqrtPrice = hook.sqrtPriceCurrent();
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14614119332);

        // ** After swap State
        (uint256 wethDelta, uint256 usdcDelta) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
        console.log("usdcDelta %s", usdcDelta);
        console.log("wethDelta %s", wethDelta);
        console.log("deltaUSDC %s", deltaUSDC);

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172867837955912361744, 239418121498, 307047761449, 47414048162101414117);
        assertEqProtocolState(1543848682939898409686214692672106, 100031037516214649242);
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14614119329;
        uint256 wethToSwapQ = quoteWETH_USDC_Out(usdcToGetFSwap);
        assertEq(wethToSwapQ, 5521289792146698531);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        // ** Swap
        uint160 preSqrtPrice = hook.sqrtPriceCurrent();
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        (uint256 wethDelta, uint256 usdcDelta) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
        console.log("usdcDelta %s", usdcDelta);
        console.log("wethDelta %s", wethDelta);
        console.log("deltaUSDC %s", deltaUSDC);
        console.log("sqrtPriceAfter %s", hook.sqrtPriceCurrent());

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172867837953809045401, 239418121498, 307047761449, 47414048161474109243);
        assertEqProtocolState(1543848682937829632319054235770132, 100031037516242283351);
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 14541229590;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        uint160 preSqrtPrice = hook.sqrtPriceCurrent();
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5436380062950283022, 1e4, "deltaWETH");

        // ** After swap State
        (uint256 wethDelta, uint256 usdcDelta) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
        console.log("usdcDelta %s", usdcDelta);
        console.log("wethDelta %s", wethDelta);
        console.log("deltaWETH %s", deltaWETH);

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157253158410295846688, 239418121498, 277892412530, 42757038473057892083);
        assertEqProtocolState(1528490415156631802711428712919168, 100033195535467736874);
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 wethToGetFSwap = 5439086117469532134;
        uint256 usdcToSwapQ = quoteUSDC_WETH_Out(wethToGetFSwap);
        assertEq(usdcToSwapQ, 14548503846); //prev case + feeLP (tokenIn + feeLP)

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5439086117469532134, 1e1, "deltaWETH");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249302282605916703, 239418121498, 277885138278, 42755888399887211211);
        assertEqProtocolState(1528486622351182584276128648738257, 100033223956290839395);
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 wethToSwap = 5521289793622710000;
        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14606848882); // less usdc to receive

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172867837955912361744, 239418121498, 307040490998, 47414048162101414117);
        assertEqProtocolState(1543844813620587397209298936306614, 100033770561590055488);
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        vm.prank(deployer.addr);
        hook.setNextLPFee(50);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14614119329;
        uint256 wethToSwapQ = quoteWETH_USDC_Out(usdcToGetFSwap);
        assertEq(wethToSwapQ, 5521565870440220543); // prev * (1 + fee)

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172868231365377314266, 239418121498, 307047761449, 47414165494748856097);
        assertEqProtocolState(1543848682937829632319054235770132, 100031313594535805362);
    }

    function test_deposit_rebalance_swap_price_up_in_protocol_fees() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% cut from trading fees
        vm.stopPrank();

        test_deposit_rebalance();

        // ** Before swap State
        assertEqBalanceState(address(hook), 0, 0);
        assertEq(hook.accumulatedFeeB(), 0);

        uint256 usdcToSwap = 14541229590;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 5436380062950283022, 1e1, "deltaWETH");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, hook.accumulatedFeeB());
        assertEq(hook.accumulatedFeeB(), 1454122);

        assertEqPositionState(157253158410295846688, 239418121498, 277893866654, 42757038473057892083);
        assertEqProtocolState(1528490415156631802711428712919168, 100032648914438673274);
    }

    function test_deposit_rebalance_swap_price_up_out_protocol_fees() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();

        // ** Before swap State
        uint256 wethToGetFSwap = 5439086117469532134;
        uint256 usdcToSwapQ = quoteUSDC_WETH_Out(wethToGetFSwap);
        assertEq(usdcToSwapQ, 14548503846);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 5439086117469532134, 1e1, "deltaWETH");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, hook.accumulatedFeeB());
        assertEq(hook.accumulatedFeeB(), 1454850);

        assertEqPositionState(157249302282605916703, 239418121498, 277886593128, 42755888399887211211);
        assertEqProtocolState(1528486622351182584276128648738257, 100032677061598280463);
    }

    function test_deposit_rebalance_swap_price_down_in_protocol_fees() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();

        // ** Before swap State
        uint256 wethToSwap = 5521289793622710000;
        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 14606848882);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), hook.accumulatedFeeQ(), 0);
        assertEq(hook.accumulatedFeeQ(), 552128979362270);

        assertEqPositionState(172867051172116770507, 239418121498, 307040490998, 47413813507285185152);
        assertEqProtocolState(1543844813620587397209298936306614, 100033218432610693217);
    }

    function test_deposit_rebalance_swap_price_down_out_protocol_fees() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(50);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14614119329;
        uint256 wethToSwapQ = quoteWETH_USDC_Out(usdcToGetFSwap);
        assertEq(wethToSwapQ, 5521565870440220543);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), hook.accumulatedFeeQ(), 0);
        assertEq(hook.accumulatedFeeQ(), 55215658704402);

        assertEqPositionState(172868152683063660494, 239418121498, 307047761449, 47414142028093906727);
        assertEqProtocolState(1543848682937829632319054235770132, 100031258378877100960);
    }

    uint160 after_swap_price_target = 1510210350358636346530480063086887;

    function test_deposit_rebalance_swap_rebalance() public {
        test_deposit_rebalance();

        {
            assertTicks(194458, 200458);
            assertApproxEqAbs(hook.sqrtPriceCurrent(), 1536110044317873455854701961688542, 1e1, "sqrtPrice");
            assertEq(hook.liquidity(), 56526950853149492, "liquidity");
        }

        // ** Swap
        {
            uint256 usdcToSwap = 50000e6; // 50k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);
            swapUSDC_WETH_In(usdcToSwap);
            assertEq(hook.sqrtPriceCurrent(), after_swap_price_target);
        }

        // ** Fail swap without oracle update
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.RebalanceConditionNotMet.selector);
        rebalanceAdapter.rebalance(slippage);

        // ** Successful 2nd rebalance
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);

        {
            assertTicks(194118, 200118);
            assertApproxEqAbs(hook.sqrtPriceCurrent(), 1510210350358636346530423690962769, 1, "sqrtPrice");
            assertEq(hook.liquidity(), 57702007741396626, "liquidity");
        }
    }

    function test_updateLiquidityAndBoundaries_on_small_deviations() public {
        test_deposit_rebalance();

        {
            assertTicks(194458, 200458);
            assertApproxEqAbs(hook.sqrtPriceCurrent(), 1536110044317873455854701961688542, 1e1, "sqrtPrice");
            assertEq(hook.liquidity(), 56526950853149492, "liquidity");
        }

        // ** Make oracle change with small price update.
        alignOracles(after_swap_price_target);

        // ** Updated liquidity and boundaries to oracle.
        vm.prank(deployer.addr);
        hook.updateLiquidityAndBoundariesToOracle();

        {
            assertTicks(194118, 200118);
            assertApproxEqAbs(hook.sqrtPriceCurrent(), 1510210350358636346530423690962769, 1, "sqrtPrice");
            assertEq(hook.liquidity(), 57496074777163322, "liquidity"); // Liquidity differs from test_deposit_rebalance_swap_rebalance because we lose assets during rebalancing.
        }
    }

    function test_updateLiquidityAndBoundaries_back_to_oracle() public {
        test_deposit_rebalance();

        // ** Protocol state.
        assertTicks(194458, 200458);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1536110044317873455854701961688542, 1e1, "sqrtPrice");
        assertEq(hook.liquidity(), 56526950853149492, "liquidity");

        part_swap_price_up_out();

        // ** Sqrt price updated after swap.
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1528486622351182584276128648738257, 1e1, "sqrtPrice");

        // ** Update liquidity and boundaries to oracle.
        vm.startPrank(deployer.addr);
        hook.setProtocolParams(
            hook.liquidityMultiplier(),
            hook.protocolFee(),
            hook.tvlCap(),
            1000,
            1000,
            hook.swapPriceThreshold()
        );
        hook.updateLiquidityAndBoundariesToOracle();
        vm.stopPrank();

        assertTicks(196458, 198458);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1536110044317873455854636894569523, 1e1, "sqrtPrice"); // Sqrt updated back.
        _liquidityCheck(hook.isInvertedPool(), hook.liquidityMultiplier());
        assertEq(hook.liquidity(), 162154085919257702, "liquidity");
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
        vm.stopPrank();

        test_deposit_rebalance();
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);

        saveBalance(address(manager));

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;

        // ** Swap Up In
        {
            uint256 usdcToSwap = 10000e6; // 100k USDC
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

            assertApproxEqAbs(deltaWETH, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 4);
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

            assertApproxEqAbs(deltaWETH, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);
        }

        // ** Swap Down Out
        {
            uint256 usdcToGetFSwap = 10000e6; //10k USDC
            uint256 wethToSwapQ = quoteWETH_USDC_Out(usdcToGetFSwap);

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

            assertApproxEqAbs((deltaWETH * (1e18 - testFee)) / 1e18, deltaX, 2);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        // ** Withdraw
        {
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

            assertApproxEqAbs(deltaWETH, deltaX, 2);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        // ** Deposit
        {
            uint256 _amountToDep = 200 ether;
            deal(address(WETH), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            hook.deposit(alice.addr, _amountToDep, 0);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 5000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 2);
        }

        // ** Swap Up out
        {
            uint256 wethToGetFSwap = 1e17;
            uint256 usdcToSwapQ = quoteUSDC_WETH_Out(wethToGetFSwap);
            console.log("usdcToSwapQ %s", usdcToSwapQ);

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
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 5);
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

            assertApproxEqAbs((deltaWETH * (1e18 - testFee)) / 1e18, deltaX, 3);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        // Rebalance
        uint256 preRebalanceTVL = calcTVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);

        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        }

        // assertBalanceNotChanged(address(manager), 1e1);
    }

    function test_lending_adapter_migration() public {
        test_deposit_rebalance();

        uint256 preTVL = calcTVL();

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
                MConstants.EULER_VAULT_CONNECT,
                MConstants.eulerUSDCVault1,
                MConstants.eulerWETHVault1,
                MConstants.merklRewardsDistributor,
                MConstants.rEUL
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

            // This is like zero interest FL.
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

        assertEqPositionState(164999999999999999995, 239418121497, 292433642119, 45067499999811762368);
        assertEqPositionState(CLbefore, CSbefore, DLbefore, DSbefore);
        assertApproxEqAbs(preTVL, calcTVL(), 1e9);

        // ** Check if the same test case works for the new lending adapter
        part_swap_price_up_in();
    }

    // ** Helpers

    function swapWETH_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(false, int256(amount), key);
    }

    function quoteWETH_USDC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapWETH_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(false, -int256(amount), key);
    }

    function swapUSDC_WETH_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(true, int256(amount), key);
    }

    function quoteUSDC_WETH_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function swapUSDC_WETH_In(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(true, -int256(amount), key);
    }
}
