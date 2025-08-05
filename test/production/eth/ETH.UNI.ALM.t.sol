// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiquidityAmounts} from "v4-core-test/utils/LiquidityAmounts.sol";

// ** contracts
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

// ** interfaces
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";

contract ETH_UNI_ALMTest is ALMTestBaseUnichain {
    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16; //50%
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 15e14; //0.15%
    uint24 feeLP = 500; //0.05%

    IERC20 WETH = IERC20(UConstants.WETH);
    IERC20 USDC = IERC20(UConstants.USDC);

    function setUp() public {
        select_unichain_fork(23302675); // If you decide to change the fork, you need to change the mock_latestRoundData() too.

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
            isNTS = 0; //TODO: native token is always 0?
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        manager = UConstants.manager;
        // deployMockUniversalRouter(); // universalRouter = UConstants.UNIVERSAL_ROUTER;
        universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER; // deployMockV4Quoter();

        create_accounts_and_tokens(UConstants.USDC, 6, "USDC", UConstants.WETH, 18, "WETH");
        create_flash_loan_adapter_morpho_unichain();
        create_lending_adapter_euler_USDC_WETH_unichain();
        oracle = _create_oracle(
            UConstants.chronicle_feed_WETH,
            UConstants.chronicle_feed_USDC,
            24 hours,
            24 hours,
            false,
            int8(6 - 18)
        );
        mock_latestRoundData(UConstants.chronicle_feed_WETH, 3634568623200000000000);
        mock_latestRoundData(UConstants.chronicle_feed_USDC, 999820000000000000);

        init_hook(false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            // hook.setNextLPFee(0); // By default, dynamic-fee-pools initialize with a 0% fee, to change - call rebalance.
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

    function test_setUp() public {
        vm.skip(true);
        assertEq(hook.owner(), deployer.addr);
        assertTicks(194466, 200466);
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
        console.log("oraclePrice %s", oracle.price());
        console.log("sqrtPrice %s", hook.sqrtPriceCurrent());
        assertTicks(-197336, -191336);

        assertApproxEqAbs(hook.sqrtPriceCurrent(), 4776888565966093100083611, 1e1, "sqrtPrice");

        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        assertEq(hook.liquidity(), 66076272993486110, "liquidity");

        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        return;
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        vm.skip(true);
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
        (, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);
        assertApproxEqAbs(deltaETH, 5439086117469532134, 1e1, "deltaETH");

        // ** After swap State
        _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(157249302282605916703, 239418121498, 277892412530, 42755888399887211211);

        assertApproxEqAbs(hook.TVL(oracle.price()), 100030489475887621071, 1e9); //1 wei drift on collateral supply
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 1528486622536030184373416970508857, 1);
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        vm.skip(true);
        test_deposit_rebalance();
        part_swap_price_up_out();
    }

    /// @dev This is needed for composability testing.
    function part_swap_price_up_out() internal {
        // ** Before swap State
        uint256 ethToGetFSwap = 5439086117469532134;
        uint256 usdcToSwapQ = quoteUSDC_ETH_Out(ethToGetFSwap);
        assertApproxEqAbs(usdcToSwapQ, 14541229590, 1e4, "deltaUSDCQuote");

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        uint160 preSqrtPrice = hook.sqrtPriceCurrent();
        saveBalance(address(manager));
        (, uint256 deltaETH) = swapUSDC_ETH_Out(ethToGetFSwap);
        assertApproxEqAbs(deltaETH, 5439086117469532134, 1e1, "deltaETH");

        // ** After swap State
        (uint256 ethDelta, uint256 usdcDelta) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
        console.log("usdcDelta %s", usdcDelta);
        console.log("ethDelta %s", ethDelta);
        console.log("deltaETH %s", deltaETH);

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249302282605916703, 239418121498, 277892412530, 42755888399887211211);
        assertEqProtocolState(1528486622536030184373521960444533, 100030489475887621071);
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 ethToSwap = 5521289793622710000;
        deal(address(swapper.addr), ethToSwap);
        assertEqBalanceState(swapper.addr, ethToSwap, 0);

        // ** Swap
        uint160 preSqrtPrice = hook.sqrtPriceCurrent();
        saveBalance(address(manager)); // TODO: then to use assertBalanceNotChanged and why it work sometimes?
        (uint256 deltaUSDC, ) = swapETH_USDC_In(ethToSwap);
        assertEq(deltaUSDC, 14614119329);

        // ** After swap State
        (uint256 ethDelta, uint256 usdcDelta) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
        console.log("usdcDelta %s", usdcDelta);
        console.log("ethDelta %s", ethDelta);
        console.log("deltaUSDC %s", deltaUSDC);

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172867837955912361744, 239418121498, 307047761449, 47414048162101414117);
        assertEqProtocolState(1543848683124746009782815587439752, 100031037508161592551);
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14614119329;
        uint256 ethToSwapQ = quoteETH_USDC_Out(usdcToGetFSwap);
        assertEq(ethToSwapQ, 5521289793478853036);

        deal(address(swapper.addr), ethToSwapQ);
        assertEqBalanceState(swapper.addr, ethToSwapQ, 0);

        // ** Swap
        uint160 preSqrtPrice = hook.sqrtPriceCurrent();
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        (uint256 ethDelta, uint256 usdcDelta) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
        console.log("usdcDelta %s", usdcDelta);
        console.log("ethDelta %s", ethDelta);
        console.log("deltaUSDC %s", deltaUSDC);
        console.log("sqrtPriceAfter %s", hook.sqrtPriceCurrent());

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172867837955707365568, 239418121498, 307047761449, 47414048162040274907);
        assertEqProtocolState(1543848683124544379891216459770667, 100031037508017735585);
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        vm.skip(true);
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
        (, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);
        assertApproxEqAbs(deltaETH, 5436380063822224884, 1e4, "deltaETH");

        // ** After swap State
        (uint256 ethDelta, uint256 usdcDelta) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());
        console.log("usdcDelta %s", usdcDelta);
        console.log("ethDelta %s", ethDelta);
        console.log("deltaETH %s", deltaETH);

        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157253158409053329533, 239418121498, 277892412530, 42757038472687316792);
        assertEqProtocolState(1528490415340257289276984340905115, 100033195529159016925);
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 ethToGetFSwap = 5439086117469532134;
        uint256 usdcToSwapQ = quoteUSDC_ETH_Out(ethToGetFSwap);
        assertEq(usdcToSwapQ, 14548503843); //prev case + feeLP (tokenIn + feeLP)

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaETH) = swapUSDC_ETH_Out(ethToGetFSwap);
        assertApproxEqAbs(deltaETH, 5439086117469532134, 1e1, "deltaETH");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(157249302282605916703, 239418121498, 277885138278, 42755888399887211211);
        assertEqProtocolState(1528486622536030184373521960444533, 100033223950103266439);
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 ethToSwap = 5521289793622710000;
        deal(address(swapper.addr), ethToSwap);
        assertEqBalanceState(swapper.addr, ethToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapETH_USDC_In(ethToSwap);
        assertEq(deltaUSDC, 14606848878); // less usdc to receive

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172867837955912361744, 239418121498, 307040490998, 47414048162101414117);
        assertEqProtocolState(1543844813805434997305899831074260, 100033770553538026179);
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(50);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 14614119329;
        uint256 ethToSwapQ = quoteETH_USDC_Out(usdcToGetFSwap);
        assertEq(ethToSwapQ, 5521565871772441659); // prev * (1 + fee)

        deal(address(swapper.addr), ethToSwapQ);
        assertEqBalanceState(swapper.addr, ethToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(172868231367275729354, 239418121498, 307047761449, 47414165495315050071);
        assertEqProtocolState(1543848683124544379891216459770667, 100031313586311324207);
    }

    function test_deposit_rebalance_swap_price_up_in_protocol_fees() public {
        vm.skip(true);
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
        (, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);
        assertApproxEqAbs(deltaETH, 5436380063822224884, 1e1, "deltaETH");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceState(address(hook), 0, hook.accumulatedFeeB());
        assertEq(hook.accumulatedFeeB(), 1454123);

        assertEqPositionState(157253158409053329533, 239418121498, 277893866654, 42757038472687316792);
        assertEqProtocolState(1528490415340257289276984340905115, 100032648907753836449);
    }

    function test_deposit_rebalance_swap_price_up_out_protocol_fees() public {
        vm.skip(true);
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();

        // ** Before swap State
        uint256 ethToGetFSwap = 5439086117469532134;
        uint256 usdcToSwapQ = quoteUSDC_ETH_Out(ethToGetFSwap);
        assertEq(usdcToSwapQ, 14548503843);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaETH) = swapUSDC_ETH_Out(ethToGetFSwap);
        assertApproxEqAbs(deltaETH, 5439086117469532134, 1e1, "deltaETH");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaETH, 0);
        assertEqBalanceState(address(hook), 0, hook.accumulatedFeeB());
        assertEq(hook.accumulatedFeeB(), 1454850);

        assertEqPositionState(157249302282605916703, 239418121498, 277886593128, 42755888399887211211);
        assertEqProtocolState(1528486622536030184373521960444533, 100032677055410501924);
    }

    function test_deposit_rebalance_swap_price_down_in_protocol_fees() public {
        vm.skip(true);
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();

        // ** Before swap State
        uint256 ethToSwap = 5521289793622710000;
        deal(address(swapper.addr), ethToSwap);
        assertEqBalanceState(swapper.addr, ethToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapETH_USDC_In(ethToSwap);
        assertEq(deltaUSDC, 14606848878);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), hook.accumulatedFeeQ(), 0);
        assertEq(hook.accumulatedFeeQ(), 552128979362270);

        assertEqPositionState(172867051172116770507, 239418121498, 307040490998, 47413813507285185152);
        assertEqProtocolState(1543844813805434997305899831074260, 100033218424558663909);
    }

    function test_deposit_rebalance_swap_price_down_out_protocol_fees() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();
        // ** Before swap State
        uint256 usdcToGetFSwap = 14614119329;
        uint256 ethToSwapQ = quoteETH_USDC_Out(usdcToGetFSwap);
        assertEq(ethToSwapQ, 4036963634589983313);

        deal(address(swapper.addr), ethToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapETH_USDC_Out(usdcToGetFSwap);

        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), hook.accumulatedFeeQ(), 0);
        assertEq(hook.accumulatedFeeQ(), 403696363458998);

        assertEqPositionState(170752097911972797140, 327170066668, 414415585063, 46783037973608523371);
        assertEqProtocolState(4759365637254375262663404, 99969013921104341535);
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

            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 2);
            assertApproxEqAbs(deltaUSDC, deltaX, 1);
        }
        return;
        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

        // ** Withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 2, 0, 0);

            (int24 tickLower, int24 tickUpper) = hook.activeTicks();
            uint128 liquidityCheck = LiquidityAmounts.getLiquidityForAmount0(
                ALMMathLib.getSqrtPriceX96FromTick(tickLower),
                ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
                lendingAdapter.getCollateralLong()
            );

            console.log("liquidity %s", hook.liquidity());
            console.log("liquidityCheck %s", liquidityCheck);

            assertApproxEqAbs(hook.liquidity(), (liquidityCheck * liquidityMultiplier) / 1e18, 1);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 10000e6; // 10k USDC
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
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 2);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

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
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                hook.liquidity(),
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaETH, deltaY, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 2);
        }

        // ** Swap Up out
        {
            uint256 ethToGetFSwap = 1e17;
            uint256 usdcToSwapQ = quoteUSDC_ETH_Out(ethToGetFSwap);
            console.log("usdcToSwapQ %s", usdcToSwapQ);

            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapUSDC_ETH_Out(ethToGetFSwap);
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
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 5);
        }

        // ** Swap Down In
        {
            uint256 ethToSwap = 10e18;
            deal(address(swapper.addr), ethToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaETH) = swapETH_USDC_In(ethToSwap);
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

            assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 3);
            assertApproxEqAbs(deltaUSDC, deltaX, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

        // Rebalance
        uint256 preRebalanceTVL = calcTVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);

        // assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV4(hook, ETH_USDC_key_unichain);

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
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
