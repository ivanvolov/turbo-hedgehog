// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** v4 imports
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolIdLibrary, PoolId} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UNICORD_R_ALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    uint256 longLeverage = 1e18;
    uint256 shortLeverage = 1e18;
    uint256 weight = 50e16; //50%
    uint256 liquidityMultiplier = 1e18;
    uint256 slippage = 10e14; //0.1%
    uint24 feeLP = 100; //0.01%

    IERC20 DAI = IERC20(MConstants.DAI);
    IERC20 USDC = IERC20(MConstants.USDC);

    function setUp() public {
        select_mainnet_fork(21881352);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = MConstants.uniswap_v3_DAI_USDC_POOL;
            ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
            SLIPPAGE_TOLERANCE_V3 = 1e15;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.DAI, 18, "DAI");
        create_lending_adapter_morpho_earn_USDC_DAI();
        create_flash_loan_adapter_morpho();
        create_oracle(false, MConstants.chainlink_feed_DAI, MConstants.chainlink_feed_USDC, 10 hours, 10 hours);
        init_hook(true, true, liquidityMultiplier, 0, 100000 ether, 100, 100, TestLib.sqrt_price_10per);

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

    function test_setUp() public view {
        assertEq(hook.owner(), deployer.addr);
        assertTicks(-276424, -276224);
    }

    uint256 amountToDep = 1e12; // 1M

    function test_deposit() public {
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(USDC), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        uint256 shares = hook.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, amountToDep, 1e1);
        assertEq(hook.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));

        assertEqPositionState(0, amountToDep - 1, 0, 0);
        assertEq(hook.sqrtPriceCurrent(), initialSQRTPrice, "sqrtPriceCurrent");
        assertApproxEqAbs(calcTVL(), amountToDep, 1e1, "tvl");
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

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        console.log("tvl %s", calcTVL());

        console.log("liquidity %s", hook.liquidity());
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        console.log("tickLower %s", tickLower);
        console.log("tickUpper %s", tickUpper);
        assertTicks(-276421, -276221);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 79240384341004934953439, 1e1, "sqrtPrice");
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();
        saveBalance(address(manager));

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

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

            // deal(address(DAI), address(swapper.addr), daiToSwapQ);
            // uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            // (uint256 deltaDAI, uint256 deltaUSDC) = swapDAI_USDC_Out(usdcToGetFSwap - 1);

            // (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            // assertApproxEqAbs((deltaDAI * (1e18 - testFee)) / 1e18, deltaY, 1);
            // assertApproxEqAbs(deltaUSDC, deltaX, 1);

            // uint256 deltaTreasuryFee = (deltaDAI * testFee * hook.protocolFee()) / 1e36;
            // console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            // treasuryFeeQ += deltaTreasuryFee;

            // assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            // assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");
            // assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");
        }
        return;

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

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
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

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

            assertApproxEqAbs((deltaDAI * (1e18 - testFee)) / 1e18, deltaY, 5e2);
            assertApproxEqAbs(deltaUSDC, deltaX, 1);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPoolsV3(hook.sqrtPriceCurrent());

        // ** Rebalance
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);

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

    // ** Helpers

    function swapDAI_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(true, int256(amount), key);
    }

    function quoteDAI_USDC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function swapDAI_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(true, -int256(amount), key);
    }

    function swapUSDC_DAI_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(false, -int256(amount), key);
    }

    function quoteUSDC_DAI_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapUSDC_DAI_In(uint256 amount) public returns (uint256, uint256) {
        return _swap_v4_single_throw_mock_router(false, -int256(amount), key);
    }
}
