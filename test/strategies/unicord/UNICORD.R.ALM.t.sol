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

contract UNICORDRALMTest is MorphoTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 1e18;
    uint256 shortLeverage = 1e18;
    uint256 weight = 50e16; //50%
    uint256 liquidityMultiplier = 1e18;
    uint256 slippage = 10e14; //0.1%
    uint24 feeLP = 100; //0.01%

    IERC20 DAI = IERC20(TestLib.DAI);
    IERC20 USDC = IERC20(TestLib.USDC);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21881352);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_DAI_USDC_POOL;
            assertEqPSThresholdCL = 1e1;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e1;
            minStepSize = 1 ether;
            slippageTolerance = 1e15;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.DAI, 18, "DAI");
        create_lending_adapter_morpho_earn_dai_usdc();
        create_flash_loan_adapter_morpho();
        create_oracle(false, TestLib.chainlink_feed_DAI, TestLib.chainlink_feed_USDC, 10 hours, 10 hours);
        init_hook(true, true, liquidityMultiplier, 0, 100000 ether, 100, 100, TestLib.sqrt_price_10per);
        assertTicks(-276424, -276224);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(2, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();
        deal(address(DAI), address(manager), 10000 ether);
    }

    uint256 amountToDep = 100000e6;

    function test_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(USDC), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, 99999999999, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(0, amountToDep - 1, 0, 0);
        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(calcTVL(), 99999999999, 1e1, "tvl");
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
        console.log("tvl %s", calcTVL());

        console.log("liquidity %s", hook.liquidity());
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        console.log("tickLower %s", tickLower);
        console.log("tickUpper %s", tickUpper);
        assertTicks(-276421, -276221);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 79240362711883211369901, 1e1, "sqrtPrice");
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();
        saveBalance(address(manager));

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;
        uint256 treasuryFeeB;
        uint256 treasuryFeeQ;

        // ** Swap Up In
        {
            console.log("SWAP UP IN");

            uint256 usdcToSwap = 1000e6; // 1k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaDAI, uint256 deltaUSDC) = swapUSDC_DAI_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaDAI, deltaY, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 1);

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");
        }

        // ** Swap Up In
        {
            console.log("SWAP UP IN");

            uint256 usdcToSwap = 10000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaDAI, uint256 deltaUSDC) = swapUSDC_DAI_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaDAI, deltaY, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 1);

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }

        // ** Swap Down Out
        {
            console.log("SWAP DOWN OUT");

            uint256 usdcToGetFSwap = 10000e6; //10k USDC
            uint256 daiToSwapQ = quoteDAI_USDC_Out(usdcToGetFSwap);

            console.log("daiToSwapQ %s", daiToSwapQ);

            deal(address(DAI), address(swapper.addr), daiToSwapQ);
            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaDAI, uint256 deltaUSDC) = swapDAI_USDC_Out(usdcToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            assertApproxEqAbs((deltaDAI * (1e18 - testFee)) / 1e18, deltaY, 1);
            assertApproxEqAbs(deltaUSDC, deltaX, 1);

            uint256 deltaTreasuryFee = (deltaDAI * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Withdraw
        {
            console.log("preTVL %s", calcTVL());
            console.log("preBalance %s", DAI.balanceOf(alice.addr));
            console.log("preBalance %s", USDC.balanceOf(alice.addr));

            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw / 4, 0, 0);

            console.log("postTVL %s", calcTVL());
            console.log("postBalance %s", DAI.balanceOf(alice.addr));
            console.log("postBalance %s", USDC.balanceOf(alice.addr));
        }

        // ** Swap Up In
        {
            console.log("SWAP UP IN");

            uint256 usdcToSwap = 10000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaDAI, uint256 deltaUSDC) = swapUSDC_DAI_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaDAI, deltaY, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 1);

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 3, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Deposit
        {
            uint256 _amountToDep = 10000e6; //10k USDC
            deal(address(DAI), address(alice.addr), _amountToDep);
            vm.prank(alice.addr);
            hook.deposit(alice.addr, _amountToDep, 0);
        }

        // ** Swap Up In
        {
            console.log("SWAP UP IN");

            uint256 usdcToSwap = 1000e6; // 10k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaDAI, uint256 deltaUSDC) = swapUSDC_DAI_In(usdcToSwap);
            uint160 postSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, postSqrtPrice);

            assertApproxEqAbs(deltaDAI, deltaY, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 1);

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 4, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }

        // ** Swap Up out
        {
            console.log("SWAP UP OUT");

            uint256 daiToGetFSwap = 100e18; //1k DAI
            uint256 usdcToSwapQ = quoteUSDC_DAI_Out(daiToGetFSwap);

            console.log("usdcToSwapQ", usdcToSwapQ);
            deal(address(USDC), address(swapper.addr), usdcToSwapQ);
            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaDAI, uint256 deltaUSDC) = swapUSDC_DAI_Out(usdcToSwapQ);

            console.log("deltaDAI", deltaDAI);
            console.log("deltaUSDC", deltaUSDC);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            assertApproxEqAbs(deltaDAI, deltaY, 1);
            assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 1);

            uint256 deltaTreasuryFee = (deltaUSDC * testFee * hook.protocolFee()) / 1e36;
            console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeB += deltaTreasuryFee;

            console.log("hook.accumulatedFeeB() %s", hook.accumulatedFeeB());
            console.log("hook.accumulatedFeeQ() %s", hook.accumulatedFeeQ());

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 4, "treasuryFee");
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }

        // ** Swap Down In
        {
            uint256 daiToSwap = 2000e18;
            deal(address(DAI), address(swapper.addr), daiToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaDAI, uint256 deltaUSDC) = swapDAI_USDC_In(daiToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaDAI", deltaDAI);
            console.log("deltaUSDC", deltaUSDC);
            console.log("deltaX", deltaX);
            console.log("deltaY", deltaY);

            assertApproxEqAbs((deltaDAI * (1e18 - testFee)) / 1e18, deltaY, 21);
            assertApproxEqAbs(deltaUSDC, deltaX, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Rebalance
        // uint256 preRebalanceTVL = calcTVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        //assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
        }

        // assertBalanceNotChanged(address(manager), 1e1);
    }

    // ** Helpers

    function swapDAI_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, int256(amount), key);
    }

    function quoteDAI_USDC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function swapDAI_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, -int256(amount), key);
    }

    function swapUSDC_DAI_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }

    function quoteUSDC_DAI_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapUSDC_DAI_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }
}
