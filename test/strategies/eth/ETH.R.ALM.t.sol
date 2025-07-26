// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";

// ** interfaces
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// This test illustrates the pool with the reversed order of currencies. The main asset first and the stable next.
contract ETHRALMTest is ALMTestBase {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16; //50%
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 15e14; //0.15%
    uint24 feeLP = 500; //0.05%

    uint256 k1 = 1425e15; //1.425
    uint256 k2 = 1425e15; //1.425

    IERC20 WETH = IERC20(TestLib.WETH);
    IERC20 USDT = IERC20(TestLib.USDT);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_WETH_USDT_POOL;
            assertEqPSThresholdCL = 1e1;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e1;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL);
        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDT, 6, "USDT", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler(TestLib.eulerUSDTVault1, 3000000 * 1e6, TestLib.eulerWETHVault1, 0);
        create_flash_loan_adapter_euler(TestLib.eulerUSDTVault2, 3000000 * 1e6, TestLib.eulerWETHVault2, 0);
        create_oracle(false, TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDT, 1 hours, 10 hours);
        init_hook(false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            // hook.setNextLPFee(0); // By default, dynamic-fee-pools initialize with a 0% fee, to change - call rebalance.
            IPositionManagerStandard(address(positionManager)).setKParams(k1, k2);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(TestLib.ONE_PERCENT_AND_ONE_BPS, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }

        approve_accounts();
    }

    function test_setUp() public view {
        assertEq(hook.owner(), deployer.addr);
        assertTicks(-200488, -194488);
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

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        assertEqBalanceStateZero(address(hook));
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        assertTicks(-197461 - 3000, -197461 + 3000);
        assertApproxEqAbs(hook.sqrtPriceCurrent(), 4086015488346380075686829, 1, "sqrtPrice");
    }

    function test_lifecycle() public {
        vm.startPrank(deployer.addr);
        hook.setNextLPFee(feeLP);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
        updateProtocolFees(20 * 1e16); // 20% from fees
        vm.stopPrank();

        test_deposit_rebalance();
        // console.log("DEPOSIT REBALANCE");

        saveBalance(address(manager));

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;
        uint256 treasuryFeeB;
        uint256 treasuryFeeQ;
        // ** Swap Up In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdtToSwap = 50e9; // 50k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            // console.log("SWAP");
            (uint256 deltaWETH, uint256 deltaUSDT) = swapUSDT_WETH_In(usdtToSwap);
            // console.log("SWAP DONE");
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            // console.log("deltaUSDT %s", deltaUSDT);
            // console.log("deltaWETH %s", deltaWETH);
            // console.log("deltaX %s", deltaX);
            // console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaY, 1);
            assertApproxEqAbs((usdtToSwap * (1e18 - testFee)) / 1e18, deltaX, 4);

            uint256 deltaTreasuryFee = (usdtToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            // console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            // console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            // console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            assertEqPositionState(
                CL - (deltaWETH * k1) / 1e18,
                CS,
                DL - usdtToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaWETH) / 1e18
            );
        }

        // ** Swap Up In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdtToSwap = 10e9; // 10k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaWETH, uint256 deltaUSDT) = swapUSDT_WETH_In(usdtToSwap);
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            // console.log("deltaUSDT %s", deltaUSDT);
            // console.log("deltaWETH %s", deltaWETH);
            // console.log("deltaX %s", deltaX);
            // console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaY, 1);
            assertApproxEqAbs((usdtToSwap * (1e18 - testFee)) / 1e18, deltaX, 1);

            uint256 deltaTreasuryFee = (usdtToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            // console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            // console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            // console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 1, "treasuryFee");

            assertEqPositionState(
                CL - (deltaWETH * k1) / 1e18,
                CS,
                DL - usdtToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaWETH) / 1e18
            );
        }

        // ** Swap Down Out
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdtToGetFSwap = 20e9; //20k USDT

            deal(address(WETH), address(swapper.addr), quoteWETH_USDT_Out(usdtToGetFSwap));

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWETH, uint256 deltaUSDT) = swapWETH_USDT_Out(usdtToGetFSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            // console.log("deltaUSDT %s", deltaUSDT);
            // console.log("deltaWETH %s", deltaWETH);
            // console.log("deltaX %s", deltaX);
            // console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaUSDT, deltaX, 1);
            assertApproxEqAbs((deltaWETH * (1e18 - testFee)) / 1e18, deltaY, 3);

            uint256 deltaTreasuryFee = (deltaWETH * testFee * hook.protocolFee()) / 1e36;
            // console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            treasuryFeeQ += deltaTreasuryFee;

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 2, "treasuryFee");

            // console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            // console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertEqPositionState(
                CL + ((deltaWETH - deltaTreasuryFee) * k1) / 1e18,
                CS,
                DL + deltaUSDT,
                DS + ((k1 - 1e18) * (deltaWETH - deltaTreasuryFee)) / 1e18
            );
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
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdtToSwap = 10e9; // 10k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaWETH, uint256 deltaUSDT) = swapUSDT_WETH_In(usdtToSwap);
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            // console.log("deltaUSDT %s", deltaUSDT);
            // console.log("deltaWETH %s", deltaWETH);
            // console.log("deltaX %s", deltaX);
            // console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaY, 1);
            assertApproxEqAbs((usdtToSwap * (1e18 - testFee)) / 1e18, deltaX, 1);

            uint256 deltaTreasuryFee = (usdtToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            // console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            // console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            // console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");

            assertEqPositionState(
                CL - (deltaWETH * k1) / 1e18,
                CS,
                DL - usdtToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaWETH) / 1e18
            );
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
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 usdtToSwap = 10e9; // 10k USDT
            deal(address(USDT), address(swapper.addr), usdtToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaWETH, uint256 deltaUSDT) = swapUSDT_WETH_In(usdtToSwap);
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            // console.log("deltaUSDT %s", deltaUSDT);
            // console.log("deltaWETH %s", deltaWETH);
            // console.log("deltaX %s", deltaX);
            // console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaWETH, deltaY, 1);
            assertApproxEqAbs((usdtToSwap * (1e18 - testFee)) / 1e18, deltaX, 1);

            uint256 deltaTreasuryFee = (usdtToSwap * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFee;
            // console.log("deltaTreasuryFee %s", deltaTreasuryFee);

            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);
            // console.log("accumulatedFeeB %s", hook.accumulatedFeeB());
            // console.log("accumulatedFeeQ %s", hook.accumulatedFeeQ());

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 2, "treasuryFee");

            assertEqPositionState(
                CL - (deltaWETH * k1) / 1e18,
                CS,
                DL - usdtToSwap + deltaTreasuryFee,
                DS - ((k1 - 1e18) * deltaWETH) / 1e18
            );
        }

        // ** Swap Up out
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            uint256 wethToGetFSwap = 1e18;
            deal(address(USDT), address(swapper.addr), quoteUSDT_WETH_Out(wethToGetFSwap));

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaWETH, uint256 deltaUSDT) = swapUSDT_WETH_Out(wethToGetFSwap);
            // console.log("SWAP DONE");
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            // console.log("deltaUSDT %s", deltaUSDT);
            // console.log("deltaWETH %s", deltaWETH);
            // console.log("deltaX %s", deltaX);
            // console.log("deltaY %s", deltaY);

            assertApproxEqAbs((deltaUSDT * (1e18 - testFee)) / 1e18, deltaX, 1);
            assertApproxEqAbs(deltaWETH, deltaY, 1);

            uint256 deltaTreasuryFeeB = (deltaUSDT * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeB += deltaTreasuryFeeB;

            assertApproxEqAbs(hook.accumulatedFeeQ(), treasuryFeeQ, 3, "treasuryFee");
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            assertEqPositionState(
                CL - ((deltaWETH) * k1) / 1e18,
                CS,
                DL - deltaUSDT + deltaTreasuryFeeB,
                DS - ((k1 - 1e18) * (deltaWETH)) / 1e18
            );
        }

        // ** Swap Down In
        {
            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = (
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                lendingAdapter.getBorrowedShort()
            );

            // console.log("CL %s", CL);
            // console.log("DL %s", DL);

            uint256 wethToSwap = 10e18;
            deal(address(WETH), address(swapper.addr), wethToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();

            (uint256 deltaWETH, uint256 deltaUSDT) = swapWETH_USDT_In(wethToSwap);
            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            // console.log("deltaUSDT %s", deltaUSDT);
            // console.log("deltaWETH %s", deltaWETH);
            // console.log("deltaX %s", deltaX);
            // console.log("deltaY %s", deltaY);

            assertApproxEqAbs(deltaUSDT, deltaX, 3);
            assertApproxEqAbs((deltaWETH * (1e18 - testFee)) / 1e18, deltaY, 2);

            uint256 deltaTreasuryFeeQ = (deltaWETH * testFee * hook.protocolFee()) / 1e36;
            treasuryFeeQ += deltaTreasuryFeeQ;
            // console.log("deltaWETH %s", deltaWETH);
            // console.log("testFee %s", testFee);
            // console.log("hook.protocolFee() %s", hook.protocolFee());

            // console.log("deltaTreasuryFeeQ %s", deltaTreasuryFeeQ);

            assertApproxEqAbs(hook.accumulatedFeeB(), treasuryFeeB, 3, "treasuryFee");
            assertEqBalanceState(address(hook), treasuryFeeQ, treasuryFeeB);

            assertEqPositionState(
                CL + ((deltaWETH - deltaTreasuryFeeQ) * k1) / 1e18,
                CS,
                DL + deltaUSDT,
                DS + ((k1 - 1e18) * (deltaWETH - deltaTreasuryFeeQ)) / 1e18
            );
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Rebalance
        uint256 preRebalanceTVL = calcTVL();
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
        _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        assertEqHookPositionState(preRebalanceTVL, weight, longLeverage, shortLeverage, slippage * 2);

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());

        // ** Full withdraw
        {
            uint256 sharesToWithdraw = hook.balanceOf(alice.addr);
            vm.prank(alice.addr);
            hook.withdraw(alice.addr, sharesToWithdraw, 0, 0);
            _liquidityCheck(hook.isInvertedPool(), liquidityMultiplier);
        }

        // assertBalanceNotChanged(address(manager), 1e1);
    }

    // ** Helpers

    function swapWETH_USDT_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, int256(amount), key);
    }

    function quoteWETH_USDT_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function swapWETH_USDT_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, -int256(amount), key);
    }

    function swapUSDT_WETH_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, int256(amount), key);
    }

    function quoteUSDT_WETH_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapUSDT_WETH_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }
}
