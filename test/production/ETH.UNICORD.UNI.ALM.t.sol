// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {PathKey} from "v4-periphery/src/interfaces/IV4Router.sol";

// This test is for routing the swap during rebalance through one of our hooks.
contract ETH_UNICORD_UNI_ALMTest is ALMTestBaseUnichain {
    using SafeERC20 for IERC20;

    IERC20 WETH = IERC20(UConstants.WETH);
    IERC20 USDC = IERC20(UConstants.USDC);
    IERC20 USDT = IERC20(UConstants.USDT);

    ALM hookALM;
    ALM hookUNICORD;
    PoolKey USDC_USDT_key_UNICORD;
    PoolKey ETH_USDC_key_ALM;
    SRebalanceAdapter rebalanceAdapterUnicord;
    SRebalanceAdapter rebalanceAdapterALM;

    uint24 feeLP = 500; //0.05%

    uint256 k1 = 1425e15; //1.425
    uint256 k2 = 1425e15; //1.425

    function setUp() public {
        select_unichain_fork(22789424);

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        {
            manager = UConstants.manager;
            // deployMockUniversalRouter();
            universalRouter = UConstants.UNIVERSAL_ROUTER;
            quoter = UConstants.V4_QUOTER;
            // deployMockV4Quoter();
            _create_accounts();
        }
    }

    function part_deploy_ETH_ALM() internal {
        uint256 longLeverage = 3e18;
        uint256 shortLeverage = 2e18;
        uint256 weight = 55e16; //50%
        uint256 liquidityMultiplier = 2e18;
        BASE = USDC;
        QUOTE = WETH;
        isNTS = 0;

        create_lending_adapter_euler_USDC_WETH_unichain();
        create_flash_loan_adapter_morpho_unichain();
        oracle = _create_oracle(
            UConstants.chronicle_feed_WETH,
            UConstants.chronicle_feed_USDC,
            24 hours,
            24 hours,
            false,
            int8(6 - 18)
        );
        mock_latestRoundData(address(UConstants.chronicle_feed_WETH), 3732706458000000000000);
        mock_latestRoundData(address(UConstants.chronicle_feed_USDC), 1000010000000000000);

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
        hookALM = hook;
        ETH_USDC_key_ALM = key;
        rebalanceAdapterALM = rebalanceAdapter;
    }

    function part_deploy_UNICORD() internal {
        uint256 longLeverage = 1e18;
        uint256 shortLeverage = 1e18;
        uint256 weight = 50e16; //50%
        uint256 liquidityMultiplier = 1e18;
        BASE = USDC;
        QUOTE = USDT;

        create_lending_adapter_euler_USDC_USDT_unichain();
        create_flash_loan_adapter_morpho_unichain();
        oracle = _create_oracle(
            AggregatorV3Interface(UConstants.chronicle_feed_USDT), // USDT
            AggregatorV3Interface(UConstants.chronicle_feed_USDC), // USDC
            24 hours,
            24 hours,
            true,
            int8(0)
        );
        mock_latestRoundData(address(UConstants.chronicle_feed_USDT), 1000535721908032161);
        mock_latestRoundData(address(UConstants.chronicle_feed_USDC), 1000010000000000000);

        init_hook(false, true, liquidityMultiplier, 0, 1000000 ether, 100, 100, type(uint256).max);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(2, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }
        hookUNICORD = hook;
        USDC_USDT_key_UNICORD = key;
        rebalanceAdapterUnicord = rebalanceAdapter;
    }

    uint256 amountToDep1 = 1e12; //1M USDC

    function part_deposit_UNICORD() public {
        deal(address(USDT), address(alice.addr), amountToDep1);

        vm.startPrank(alice.addr);
        USDT.approve(address(hookUNICORD), type(uint256).max);
        uint256 shares = hookUNICORD.deposit(alice.addr, amountToDep1, 0);
        vm.stopPrank();

        assertApproxEqAbs(shares, amountToDep1, 1);
        assertEqBalanceStateZero(alice.addr);
    }

    uint256 amountToDep2 = 100 ether;

    function part_deposit_ETHALM() public {
        deal(address(WETH), address(alice.addr), amountToDep2);
        vm.startPrank(alice.addr);
        WETH.approve(address(hookALM), type(uint256).max);
        uint256 shares = hookALM.deposit(alice.addr, amountToDep2, 0);
        vm.stopPrank();

        assertApproxEqAbs(shares, amountToDep2, 1);
        assertEqBalanceStateZero(alice.addr);
    }

    function part_rebalance_UNICORD() public {
        vm.prank(deployer.addr);
        rebalanceAdapterUnicord.rebalance(10e14);
    }

    function part_rebalance_ETH_ALM(uint256 slippage) public {
        vm.prank(deployer.addr);
        rebalanceAdapterALM.rebalance(slippage);
    }

    function par_swap_up_in_ETH_ALM() public {
        uint256 usdcToSwap = 10000e6; // 100k USDC
        deal(address(USDC), address(swapper.addr), usdcToSwap);

        uint160 preSqrtPrice = hookALM.sqrtPriceCurrent();
        (uint256 deltaETH, uint256 deltaUSDC) = swapUSDC_ETH_In(usdcToSwap);

        (uint256 deltaX, uint256 deltaY) = _checkSwap(hookALM.liquidity(), preSqrtPrice, hookALM.sqrtPriceCurrent());

        console.log("deltaUSDC %s", deltaUSDC);
        console.log("deltaETH %s", deltaETH);
        console.log("deltaX %s", deltaX);
        console.log("deltaY %s", deltaY);

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;
        assertApproxEqAbs(deltaETH, deltaY, 1);
        assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 1);

        console.log("sqrtPriceAfter %s", hookALM.sqrtPriceCurrent());
    }

    function par_swap_down_in_ETH_ALM() public {
        uint256 ethToSwap = 10e18;
        deal(address(swapper.addr), ethToSwap);

        uint160 preSqrtPrice = hookALM.sqrtPriceCurrent();
        console.log("preSqrtPrice %s", hookALM.sqrtPriceCurrent());

        (uint256 deltaETH, uint256 deltaUSDC) = swapETH_USDC_In(ethToSwap);

        (uint256 deltaX, uint256 deltaY) = _checkSwap(hookALM.liquidity(), preSqrtPrice, hookALM.sqrtPriceCurrent());

        console.log("deltaUSDC %s", deltaUSDC);
        console.log("deltaETH %s", deltaETH);
        console.log("deltaX %s", deltaX);
        console.log("deltaY %s", deltaY);

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;
        assertApproxEqAbs(deltaUSDC, deltaX, 1);
        assertApproxEqAbs((ethToSwap * (1e18 - testFee)) / 1e18, deltaY, 1);

        console.log("sqrtPriceAfter %s", hookALM.sqrtPriceCurrent());
    }

    function par_swap_down_out_ETH_ALM() public {
        uint256 usdcFromSwap = 30e9;

        assertApproxEqAbs(BASE.balanceOf(swapper.addr), 0, 0);
        assertApproxEqAbs(swapper.addr.balance, 0, 0);
        assertEq(address(universalRouter).balance, 0);

        uint256 extraETH = 1e18;
        uint256 ethForSwap = quoteETH_USDC_Out(usdcFromSwap);
        deal(address(swapper.addr), ethForSwap + extraETH); // add extraETH to check what router does not steel eth.

        uint160 preSqrtPrice = hookALM.sqrtPriceCurrent();
        (uint256 deltaETH, uint256 deltaUSDC) = swapETH_USDC_Out(usdcFromSwap);

        (uint256 deltaX, uint256 deltaY) = _checkSwap(hookALM.liquidity(), preSqrtPrice, hookALM.sqrtPriceCurrent());

        // console.log("deltaUSDC %s", deltaUSDC);
        // console.log("deltaETH %s", deltaETH);
        // console.log("deltaX %s", deltaX);
        // console.log("deltaY %s", deltaY);

        assertApproxEqAbs(deltaUSDC, deltaX, 1);
        assertApproxEqAbs(usdcFromSwap, deltaUSDC, 1);

        // uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;
        // assertApproxEqAbs((deltaETH * (1e18 - testFee)) / 1e18, deltaY, 1e9);

        assertApproxEqAbs(BASE.balanceOf(swapper.addr), deltaUSDC, 0);
        assertApproxEqAbs(swapper.addr.balance, 1e18, 0); // check what extraETH is still in place.
        assertEq(address(universalRouter).balance, 0);
    }

    function par_swap_up_out_ETH_ALM() public {
        uint256 ethFromSwap = 2671181763613173696;
        uint256 usdcToSwap = quoteUSDC_ETH_Out(ethFromSwap);
        deal(address(USDC), address(swapper.addr), usdcToSwap);

        uint160 preSqrtPrice = hookALM.sqrtPriceCurrent();
        (uint256 deltaETH, uint256 deltaUSDC) = swapUSDC_ETH_Out(ethFromSwap);
        (uint256 deltaX, uint256 deltaY) = _checkSwap(hookALM.liquidity(), preSqrtPrice, hookALM.sqrtPriceCurrent());

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;

        console.log("deltaUSDC %s", deltaUSDC);
        console.log("deltaETH %s", deltaETH);
        console.log("deltaX %s", deltaX);
        console.log("deltaY %s", deltaY);

        assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaX, 1);
        assertApproxEqAbs(ethFromSwap, deltaY, 1);
    }

    function part_test_lifecycle() public {
        part_deploy_UNICORD();

        {
            vm.startPrank(deployer.addr);
            uint8[4] memory config = [2, 2, 0, 0];
            setSwapAdapterToV4SingleSwap(USDC_USDT_key_unichain, config);
            vm.stopPrank();
        }

        part_deposit_UNICORD();
        part_rebalance_UNICORD();

        part_deploy_ETH_ALM();

        {
            // BASE = USDC, QUOTE = WETH
            PathKey[] memory path0 = new PathKey[](2);
            PathKey[] memory path1 = new PathKey[](2);
            PathKey[] memory path2 = new PathKey[](2);
            PathKey[] memory path3 = new PathKey[](2);

            // exactIn, base => quote
            // USDC->USDT->ETH->WETH
            {
                path0[0] = PathKey(
                    USDC_USDT_key_UNICORD.currency1,
                    USDC_USDT_key_UNICORD.fee,
                    USDC_USDT_key_UNICORD.tickSpacing,
                    USDC_USDT_key_UNICORD.hooks,
                    abi.encodePacked(uint8(1))
                );
                path0[1] = PathKey(
                    ETH_USDT_key_unichain.currency1,
                    ETH_USDT_key_unichain.fee,
                    ETH_USDT_key_unichain.tickSpacing,
                    ETH_USDT_key_unichain.hooks,
                    abi.encodePacked(uint8(2))
                );
            }

            // exactOut, quote => base
            // WETH->ETH->USDT->USDC
            {
                path1[0] = PathKey(
                    ETH_USDT_key_unichain.currency0,
                    ETH_USDT_key_unichain.fee,
                    ETH_USDT_key_unichain.tickSpacing,
                    ETH_USDT_key_unichain.hooks,
                    abi.encodePacked(uint8(2))
                );
                path1[1] = PathKey(
                    USDC_USDT_key_UNICORD.currency1,
                    USDC_USDT_key_UNICORD.fee,
                    USDC_USDT_key_UNICORD.tickSpacing,
                    USDC_USDT_key_UNICORD.hooks,
                    abi.encodePacked(uint8(1))
                );
            }

            // exactOut, base => quote
            // USDC->USDT->ETH->WETH
            {
                path2[0] = PathKey(
                    USDC_USDT_key_UNICORD.currency0,
                    USDC_USDT_key_UNICORD.fee,
                    USDC_USDT_key_UNICORD.tickSpacing,
                    USDC_USDT_key_UNICORD.hooks,
                    abi.encodePacked(uint8(1))
                );
                path2[1] = PathKey(
                    ETH_USDT_key_unichain.currency1,
                    ETH_USDT_key_unichain.fee,
                    ETH_USDT_key_unichain.tickSpacing,
                    ETH_USDT_key_unichain.hooks,
                    abi.encodePacked(uint8(2))
                );
            }

            // exactIn, quote => base
            // WETH->ETH->USDT->USDC
            {
                path3[0] = PathKey(
                    ETH_USDT_key_unichain.currency1,
                    ETH_USDT_key_unichain.fee,
                    ETH_USDT_key_unichain.tickSpacing,
                    ETH_USDT_key_unichain.hooks,
                    abi.encodePacked(uint8(2))
                );
                path3[1] = PathKey(
                    USDC_USDT_key_UNICORD.currency0,
                    USDC_USDT_key_UNICORD.fee,
                    USDC_USDT_key_UNICORD.tickSpacing,
                    USDC_USDT_key_UNICORD.hooks,
                    abi.encodePacked(uint8(1))
                );
            }

            vm.startPrank(deployer.addr);
            setSwapAdapterToV4MultihopSwap(
                abi.encode(false, path0), // always auto wrap eth
                abi.encode(true, path1),
                abi.encode(false, path2),
                abi.encode(true, path3)
            );
            vm.stopPrank();
        }
        part_deposit_ETHALM();

        vm.startPrank(deployer.addr);
        rebalanceAdapterALM.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
        hookALM.setNextLPFee(feeLP);
        vm.stopPrank();

        part_rebalance_ETH_ALM(20e14);
        console.log("oracle.price()", oracle.price());
        console.log("sqrt price %s", hookALM.sqrtPriceCurrent());

        // Permit2 approvals
        {
            vm.startPrank(swapper.addr);
            USDC.forceApprove(address(UConstants.PERMIT_2), type(uint256).max);
            UConstants.PERMIT_2.approve(address(USDC), address(universalRouter), type(uint160).max, type(uint48).max);
            // Can't approve ETH to permit. And don't need to.
        }
    }

    function test_lifecycle_0() public {
        part_test_lifecycle();

        par_swap_up_in_ETH_ALM();
        alignOraclesAndPoolsV4(hookALM, ETH_USDT_key_unichain);
        part_rebalance_ETH_ALM(3e14);
    }

    function test_lifecycle_1() public {
        part_test_lifecycle();

        par_swap_up_out_ETH_ALM();
        alignOraclesAndPoolsV4(hookALM, ETH_USDT_key_unichain);
        part_rebalance_ETH_ALM(3e14);
    }

    function test_lifecycle_3() public {
        part_test_lifecycle();

        par_swap_down_in_ETH_ALM();
        alignOraclesAndPoolsV4(hookALM, ETH_USDT_key_unichain);
        part_rebalance_ETH_ALM(3e14);
    }

    function test_lifecycle_4() public {
        part_test_lifecycle();

        par_swap_down_out_ETH_ALM();
        alignOraclesAndPoolsV4(hookALM, ETH_USDT_key_unichain);
        part_rebalance_ETH_ALM(3e14);
    }

    // ** Helpers

    function quoteETH_USDC_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(true, amount);
    }

    function quoteUSDC_ETH_Out(uint256 amount) public returns (uint256) {
        return _quoteOutputSwap(false, amount);
    }

    function swapETH_USDC_In(uint256 amount) public returns (uint256, uint256) {
        console.log("swapETH_USDC_In");
        return swapAndReturnDeltas(true, true, amount);
    }

    function swapETH_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        console.log("swapETH_USDC_Out");
        return swapAndReturnDeltas(true, false, amount);
    }

    function swapUSDC_ETH_In(uint256 amount) public returns (uint256, uint256) {
        console.log("swapUSDC_ETH_In");
        return swapAndReturnDeltas(false, true, amount);
    }

    function swapUSDC_ETH_Out(uint256 amount) public returns (uint256, uint256) {
        console.log("swapUSDC_ETH_Out");
        return swapAndReturnDeltas(false, false, amount);
    }

    function swapAndReturnDeltas(bool zeroForOne, bool isExactInput, uint256 amount) public returns (uint256, uint256) {
        console.log("START: swapAndReturnDeltas");
        int256 usdcBefore = int256(USDC.balanceOf(swapper.addr));
        int256 ethBefore = int256(swapper.addr.balance);

        vm.startPrank(swapper.addr);
        _swap_v4_single_throw_router(zeroForOne, isExactInput, amount, ETH_USDC_key_ALM);
        vm.stopPrank();

        int256 usdcAfter = int256(USDC.balanceOf(swapper.addr));
        int256 ethAfter = int256(swapper.addr.balance);
        console.log("END: swapAndReturnDeltas");
        return (abs(ethAfter - ethBefore), abs(usdcAfter - usdcBefore));
    }
}
