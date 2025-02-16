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

contract ETHALMTest is ALMTestBase {
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
            invertedPool = true;
            assertEqPSThresholdCL = 1e5;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e5;

            assertLDecimals = 18;
            assertSDecimals = 8;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        console.log("v3Pool: initialPrice %s", getV3PoolPrice(TARGET_SWAP_POOL));
        console.log("v3Pool: initialSQRTPrice %s", initialSQRTPrice);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, "USDC", TestLib.WETH, "WETH");
        create_lending_adapter(
            TestLib.eulerUSDCVault1,
            TestLib.eulerWETHVault1,
            TestLib.eulerUSDCVault2,
            TestLib.eulerWETHVault2
        );
        create_oracle(TestLib.chainlink_feed_WETH);
        console.log("oracle: initialPrice %s", oracle.price());
        init_hook(6, 18);
        assertEq(hook.tickLower(), 200459);
        assertEq(hook.tickUpper(), 194459);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setIsInvertAssets(false);
            hook.setIsInvertedPool(true);
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

    function test_withdraw() public {
        vm.expectRevert(IALM.NotZeroShares.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 0, 0);

        vm.expectRevert(IALM.NotEnoughSharesToWithdraw.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, 10, 0);
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

    function test_deposit_rebalance_revert_no_rebalance_needed() public {
        test_deposit_rebalance();

        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
    }

    function test_deposit_rebalance_withdraw() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());
        part_withdraw();
    }

    // @Notice: this is needed for composability testing
    function part_withdraw() public {
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, 0);
        assertEq(hook.balanceOf(alice.addr), 0);

        assertEqBalanceState(alice.addr, 99720500710190637665, 0);
        assertEqPositionState(0, 0, 0, 0);
        assertApproxEqAbs(hook.TVL(), 0, 1e4, "tvl");
        assertEqBalanceStateZero(address(hook));
    }

    function test_deposit_rebalance_withdraw_on_shutdown() public {
        test_deposit_rebalance();

        alignOraclesAndPools(hook.sqrtPriceCurrent());

        vm.prank(deployer.addr);
        hook.setShutdown(true);

        part_withdraw();
    }

    function test_deposit_rebalance_withdraw_revert_min_out() public {
        test_deposit_rebalance();
        alignOraclesAndPools(hook.sqrtPriceCurrent());
        assertEqBalanceStateZero(alice.addr);

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.expectRevert(IALM.NotMinOutWithdraw.selector);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw, type(uint256).max);
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        test_deposit_rebalance();
        part_swap_price_up_in();
    }

    // @Notice: this is needed for composability testing
    function part_swap_price_up_in() public {
        uint256 usdcToSwap = 17897776432;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 4626805947735540197, 1e4, "tvl");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173406801524476855220, 307920000000, 444249109866, 38073607472212395416);

        assertEq(hook.sqrtPriceCurrent(), 1270692167884249415165740426235478);
        assertApproxEqAbs(hook.TVL(), 99913835812202105946, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        test_deposit_rebalance();

        uint256 wethToGetFSwap = 4626903915919660000;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 17898157290);
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 4626903915919660000, 1e1, "tvl");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173406661919814484500, 307920000000, 444248729008, 38073565835734144500);

        assertEq(hook.sqrtPriceCurrent(), 1270692033691648863352713011702213);
        assertApproxEqAbs(hook.TVL(), 99913836793875091884, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_revert_deviations() public {
        test_deposit_rebalance();

        vm.prank(deployer.addr);
        hook.setSwapPriceThreshold(3 * 1e15);

        uint256 wethToGetFSwap = 4626903915919660000;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        vm.expectRevert();
        swapUSDC_WETH_Out(wethToGetFSwap);
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        uint256 wethToSwap = 4696832668752530000;
        test_deposit_rebalance();

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 17987871838);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186692986552972355250, 307920000000, 480134758137, 42036153884219825249);

        assertEq(hook.sqrtPriceCurrent(), 1283463286628492184493879892596945);
        assertApproxEqAbs(hook.TVL(), 99914105171480511295, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        test_deposit_rebalance();

        uint256 usdcToGetFSwap = 17987491283;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 4696732800805156176);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186692844241147347549, 307920000000, 480134377581, 42036111440342191374);

        assertEq(hook.sqrtPriceCurrent(), 1283463149833677722315484726714060);
        assertApproxEqAbs(hook.TVL(), 99914104174928305045, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        uint256 usdcToSwap = 17897776432;

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);
        assertApproxEqAbs(deltaWETH, 4624504019982289378, 1e4, "tvl");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173410081771525237636, 307920000000, 444249109866, 38074585791507527014);

        assertEq(hook.sqrtPriceCurrent(), 1270695320965775488682522591655933);
        assertApproxEqAbs(hook.TVL(), 99916137739955356764, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        uint256 wethToGetFSwap = 4626903915919660000;
        (uint256 usdcToSwapQ, ) = hook.quoteSwap(true, int256(wethToGetFSwap));
        assertEq(usdcToSwapQ, 17907106368);
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
        assertApproxEqAbs(deltaWETH, 4626903915919660000, 1e1, "tvl");

        assertEqBalanceState(swapper.addr, deltaWETH, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173406661919814484500, 307920000000, 444239779931, 38073565835734144500);

        assertEq(hook.sqrtPriceCurrent(), 1270692033691648863352713011702213);
        assertApproxEqAbs(hook.TVL(), 99916161833365868709, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        uint256 wethToSwap = 4696832668752530000;
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        deal(address(WETH), address(swapper.addr), wethToSwap);
        assertEqBalanceState(swapper.addr, wethToSwap, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_In(wethToSwap);
        assertEq(deltaUSDC, 17978922963);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186692986552972355250, 307920000000, 480125809262, 42036153884219825249);

        assertEq(hook.sqrtPriceCurrent(), 1283460069868909267964367933948804);
        assertApproxEqAbs(hook.TVL(), 99916430158490124182, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        test_deposit_rebalance();
        vm.prank(deployer.addr);
        positionManager.setFees(5 * 1e14);

        uint256 usdcToGetFSwap = 17987491283;
        (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
        assertEq(wethToSwapQ, 4699081167205558754);

        deal(address(WETH), address(swapper.addr), wethToSwapQ);
        assertEqBalanceState(swapper.addr, wethToSwapQ, 0);

        (uint256 deltaUSDC, ) = swapWETH_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186696190663267921224, 307920000000, 480134377581, 42037109496062362469);

        assertEq(hook.sqrtPriceCurrent(), 1283463149833677722315484726714060);
        assertApproxEqAbs(hook.TVL(), 99916452541328707625, 1e1, "tvl");
    }

    function test_deposit_rebalance_swap_rebalance() public {
        test_deposit_rebalance_swap_price_up_in();

        // ** Fail swap without oracle update
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
        rebalanceAdapter.rebalance(slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Second rebalance
        {
            vm.prank(deployer.addr);
            rebalanceAdapter.rebalance(slippage);

            assertEqBalanceStateZero(address(hook));
            assertEqPositionState(180477474306962171598, 311830756139, 467628623007, 40146211506948696394);
            assertApproxEqAbs(hook.TVL(), 100255384799449037450, 1e1, "tvl");
        }
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
            uint256 usdcToSwap = 100000e6; // 100k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1e15);
            assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        }

        // ** Swap Up In
        {
            console.log("Swap Up In");
            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1e15);
            assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        }

        // ** Swap Down Out
        {
            console.log("Swap Down Out");
            uint256 usdcToGetFSwap = 200000e6; //200k USDC
            (, uint256 wethToSwapQ) = hook.quoteSwap(false, int256(usdcToGetFSwap));
            deal(address(WETH), address(swapper.addr), wethToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_Out(usdcToGetFSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, (deltaX * (1e18 + fee)) / 1e18, 7e14);
            assertApproxEqAbs(deltaUSDC, deltaY, 2e6);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 2, 0);
        }

        {
            console.log("Swap Up In");
            uint256 usdcToSwap = 50000e6; // 50k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1e15);
            assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Deposit
        {
            uint256 _amountToDep = 200 ether;
            deal(address(WETH), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            hook.deposit(alice.addr, _amountToDep);
        }

        // ** Swap Up In
        {
            console.log("Swap Up In");
            uint256 usdcToSwap = 10000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 1e15);
            assertApproxEqAbs((usdcToSwap * (1e18 - fee)) / 1e18, deltaY, 1e7);
        }

        // ** Swap Up out
        {
            console.log("Swap Up Out");
            uint256 wethToGetFSwap = 5e18;
            (uint256 usdcToSwapQ, uint256 ethToSwapQ) = hook.quoteSwap(true, int256(wethToGetFSwap));
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_Out(wethToGetFSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs(deltaWETH, deltaX, 3e14);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 + fee)) / 1e18, 1e7);
        }

        // ** Swap Down In
        {
            console.log("Swap Down In");
            uint256 wethToSwap = 10e18;
            deal(address(WETH), address(swapper.addr), wethToSwap);

            uint256 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapWETH_USDC_In(wethToSwap);
            uint256 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(
                uint256(hook.liquidity()) / 1e12,
                uint160(preSqrtPrice),
                uint160(postSqrtPrice)
            );
            assertApproxEqAbs((deltaWETH * (1e18 - fee)) / 1e18, deltaX, 42e13);
            assertApproxEqAbs(deltaUSDC, deltaY, 1e7);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Rebalance
        uint256 preRebalanceTVL = hook.TVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0);
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
                0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9,
                0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2,
                0xcBC9B61177444A793B85442D3a953B90f6170b7D,
                0x716bF454066a84F39A2F78b5707e79a9d64f1225
            );
            IBase(address(newAdapter)).setTokens(address(USDC), address(WETH), 6, 18);
            IBase(address(newAdapter)).setComponents(
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                migrationContract.addr,
                address(swapAdapter)
            );
        }

        // ** Withdraw collateral
        {
            IBase(address(lendingAdapter)).setComponents(
                address(hook),
                migrationContract.addr,
                migrationContract.addr,
                migrationContract.addr,
                migrationContract.addr,
                migrationContract.addr
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
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                address(rebalanceAdapter),
                address(swapAdapter)
            );

            IBase(address(newAdapter)).setComponents(
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                address(rebalanceAdapter),
                address(swapAdapter)
            );

            IBase(address(positionManager)).setComponents(
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                address(rebalanceAdapter),
                address(swapAdapter)
            );

            IBase(address(rebalanceAdapter)).setComponents(
                address(hook),
                address(newAdapter),
                address(positionManager),
                address(oracle),
                address(rebalanceAdapter),
                address(swapAdapter)
            );
            vm.stopPrank();
        }

        assertEqBalanceStateZero(migrationContract.addr);

        // ** Check if states are the same
        assertEqBalanceStateZero(address(hook));
        assertEqPositionState(180 * 1e18, 307920000000, 462146886298, 4004e16);
        assertApproxEqAbs(hook.TVL(), 99890660873473629515, 1e1, "tvl");

        // ** Check if the same test case works for the new lending adapter
        part_swap_price_up_in();
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
