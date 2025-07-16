// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** v4 imports
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";
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
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";

contract UNICORDALMTest is MorphoTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 1e18;
    uint256 shortLeverage = 1e18;
    uint256 weight = 50e16; //50%
    uint256 liquidityMultiplier = 1e18;
    uint256 slippage = 30e14; //0.3%
    uint24 feeLP = 100; //0.01%

    IERC20 USDT = IERC20(TestLib.USDT);
    IERC20 USDC = IERC20(TestLib.USDC);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21881352);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_USDC_USDT_POOL;
            assertEqPSThresholdCL = 1e1;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e1;
            minStepSize = 1 ether;
            slippageTolerance = 1e15;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.USDT, 6, "USDT");
        create_lending_adapter_morpho_earn();
        create_flash_loan_adapter_morpho();
        create_oracle(true, TestLib.chainlink_feed_USDT, TestLib.chainlink_feed_USDC, 10 hours, 10 hours);
        init_hook(false, true, liquidityMultiplier, 0, 1000000 ether, 100, 100, TestLib.sqrt_price_1per);
        assertTicks(-99, 101);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(2, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();
    }

    uint256 amountToDep = 100000e6;

    function test_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(USDT), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, 99999999999, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEqProtocolState(initialSQRTPrice, 99999999999);
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_withdraw() public {
        test_deposit();

        uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
        vm.prank(alice.addr);
        hook.withdraw(alice.addr, sharesToWithdraw / 2, 0, 0);
    }

    function test_deposit_rebalance() public {
        test_deposit();
        // uint256 preRebalanceTVL = calcTVL();

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        // assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);
    }

    function test_deposit_rebalance_swap_price_up_in() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 17897776432;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
        assertApproxEqAbs(deltaUSDT, 4626805947735540197, 1e4, "tvl");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(173406801524476855220, 307920000000, 444249109866, 38073607472212395416);
        assertEqProtocolState(1270692167884249415165740426235478, 99913835812202105946);
    }

    function test_deposit_rebalance_swap_price_up_out() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToGetFSwap = 4626903915919660000;
        (uint256 usdcToSwapQ, ) = _quoteOutputSwap(true, usdtToGetFSwap);
        assertEq(usdcToSwapQ, 12371660056);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaUSDT) = swapUSDC_USDT_Out(usdtToGetFSwap);
        assertApproxEqAbs(deltaUSDT, 4626903915919660000, 1e1, "tvl");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(173406661919814484500, 307920000000, 444248729008, 38073565835734144500);
        assertEqProtocolState(1270692033691648863352713011702213, 99913836793875091884);
    }

    function test_deposit_rebalance_swap_price_up_out_revert_deviations() public {
        vm.skip(true);
        vm.startPrank(deployer.addr);
        updateProtocolPriceThreshold(3 * 1e15);
        vm.stopPrank();
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToGetFSwap = 4626903915919660000;
        (uint256 usdcToSwapQ, ) = _quoteOutputSwap(true, usdtToGetFSwap);
        deal(address(USDC), address(swapper.addr), usdcToSwapQ);

        // ** Swap
        bool hasReverted = false;
        try this.swapUSDC_USDT_Out(usdtToGetFSwap) {
            hasReverted = false;
        } catch {
            hasReverted = true;
        }
        assertTrue(hasReverted, "Expected function to revert but it didn't");
    }

    function test_deposit_rebalance_swap_price_down_in() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToSwap = 4696832668752530000;
        deal(address(USDT), address(swapper.addr), usdtToSwap);
        assertEqBalanceState(swapper.addr, usdtToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapUSDT_USDC_In(usdtToSwap);
        assertEq(deltaUSDC, 17987871838);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186692986552972355250, 307920000000, 480134758137, 42036153884219825249);
        assertEqProtocolState(1283463286628492184493879892596945, 99914105171480511295);
    }

    function test_deposit_rebalance_swap_price_down_out() public {
        vm.skip(true);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 17987491283;
        (, uint256 usdtToSwapQ) = _quoteOutputSwap(false, usdcToGetFSwap);
        assertEq(usdtToSwapQ, 4696732800805156176);

        deal(address(USDT), address(swapper.addr), usdtToSwapQ);
        assertEqBalanceState(swapper.addr, usdtToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapUSDT_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186692844241147347549, 307920000000, 480134377581, 42036111440342191374);
        assertEqProtocolState(1283463149833677722315484726714060, 99914104174928305045);
    }

    function test_deposit_rebalance_swap_price_up_in_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToSwap = 17897776432;
        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
        assertApproxEqAbs(deltaUSDT, 4624504019982289378, 1e4, "tvl");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173410081771525237636, 307920000000, 444249109866, 38074585791507527014);
        assertEqProtocolState(1270695320965775488682522591655933, 99916137739955356764);
    }

    function test_deposit_rebalance_swap_price_up_out_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToGetFSwap = 4626903915919660000;
        (uint256 usdcToSwapQ, ) = _quoteOutputSwap(true, usdtToGetFSwap);
        assertEq(usdcToSwapQ, 17907106368);

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        // ** Swap
        saveBalance(address(manager));
        (, uint256 deltaUSDT) = swapUSDC_USDT_Out(usdtToGetFSwap);
        assertApproxEqAbs(deltaUSDT, 4626903915919660000, 1e1, "tvl");

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(173406661919814484500, 307920000000, 444239779931, 38073565835734144500);
        assertEqProtocolState(1270692033691648863352713011702213, 99916161833365868709);
    }

    function test_deposit_rebalance_swap_price_down_in_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdtToSwap = 4696832668752530000;
        deal(address(USDT), address(swapper.addr), usdtToSwap);
        assertEqBalanceState(swapper.addr, usdtToSwap, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapUSDT_USDC_In(usdtToSwap);
        assertEq(deltaUSDC, 17978922963);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186692986552972355250, 307920000000, 480125809262, 42036153884219825249);
        assertEqProtocolState(1283460069868909267964367933948804, 99916430158490124182);
    }

    function test_deposit_rebalance_swap_price_down_out_fees() public {
        vm.skip(true);
        vm.prank(deployer.addr);
        hook.setNextLPFee(feeLP);
        test_deposit_rebalance();

        // ** Before swap State
        uint256 usdcToGetFSwap = 17987491283;
        (, uint256 usdtToSwapQ) = _quoteOutputSwap(false, usdcToGetFSwap);
        assertEq(usdtToSwapQ, 4699081167205558754);

        deal(address(USDT), address(swapper.addr), usdtToSwapQ);
        assertEqBalanceState(swapper.addr, usdtToSwapQ, 0);

        // ** Swap
        saveBalance(address(manager));
        (uint256 deltaUSDC, ) = swapUSDT_USDC_Out(usdcToGetFSwap);
        assertEq(deltaUSDC, usdcToGetFSwap);

        // ** After swap State
        assertBalanceNotChanged(address(manager), 1e1);
        assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        assertEqBalanceState(address(hook), 0, 0);

        assertEqPositionState(186696190663267921224, 307920000000, 480134377581, 42037109496062362469);
        assertEqProtocolState(1283463149833677722315484726714060, 99916452541328707625);
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);

        test_deposit_rebalance();
        saveBalance(address(manager));

        //rebalanceAdapter.setRebalancePriceThreshold(1e15);
        //rebalanceAdapter.setRebalanceTimeThreshold(60 * 60 * 24 * 7);
        vm.stopPrank();

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Swap Up In
        {
            uint256 usdcToSwap = 10000e6; // 1k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaUSDT, (deltaX * (1e18 - feeLP)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);
        }

        // ** Swap Up In
        {
            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaUSDT, (deltaX * (1e18 - feeLP)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);
        }

        // ** Swap Down Out
        {
            uint256 usdcToGetFSwap = 10000e6; //10k USDC
            (, uint256 usdtToSwapQ) = _quoteOutputSwap(false, usdcToGetFSwap);
            deal(address(USDT), address(swapper.addr), usdtToSwapQ);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDT_USDC_Out(usdcToGetFSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);
            assertApproxEqAbs(deltaUSDT, (deltaX * (1e18 + feeLP)) / 1e18, 1);
            assertApproxEqAbs(deltaUSDC, deltaY, 1);
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
            uint256 usdcToSwap = 5000e6; // 5k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);
            assertApproxEqAbs(deltaUSDT, (deltaX * (1e18 - feeLP)) / 1e18, 1);
            assertApproxEqAbs(usdcToSwap, deltaY, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Deposit
        {
            uint256 _amountToDep = 100000e6; //100k USDC
            deal(address(USDT), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            hook.deposit(alice.addr, _amountToDep, 0);
        }

        // ** Swap Down In
        {
            uint256 usdtToSwap = 10000e6;
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDT_USDC_In(usdtToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);
            assertApproxEqAbs(deltaUSDT, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 - feeLP)) / 1e18, 1);
        }

        // ** Swap Up Out
        {
            uint256 usdtToGetFSwap = 10000e6; //10k USDT
            (uint256 usdcToSwapQ, ) = _quoteOutputSwap(true, usdtToGetFSwap);
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaUSDT) = swapUSDC_USDT_Out(usdtToGetFSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);
            assertApproxEqAbs(deltaUSDT, deltaX, 1);
            assertApproxEqAbs(deltaUSDC, (deltaY * (1e18 + feeLP)) / 1e18, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Rebalance
        // uint256 preRebalanceTVL = calcTVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        // assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        }

        assertBalanceNotChanged(address(manager), 1e1);
    }

    // ** Helpers

    function swapUSDT_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, int256(amount), key);
    }

    function swapUSDT_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }

    function swapUSDC_USDT_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, int256(amount), key);
    }

    function swapUSDC_USDT_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, -int256(amount), key);
    }
}
