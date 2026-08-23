// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";
import {ALM} from "@src/ALM.sol";
import {BaseStrategyHook} from "@src/core/base/BaseStrategyHook.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

// ** interfaces
import {IFlashLoanAdapter} from "@src/interfaces/IFlashLoanAdapter.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {IPositionManagerStandard} from "@test/interfaces/IPositionManagerStandard.sol";

contract REB_PROD_ALMTest is ALMTestBaseUnichain {
    IERC20 WETH = IERC20(UConstants.WETH);
    IERC20 USDC = IERC20(UConstants.USDC);

    function setUp() public {
        select_unichain_fork(32845331);

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
            IS_NTS = true;
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        manager = UConstants.manager;
        universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER;

        part_connect_live_hook();
    }

    function part_connect_live_hook() public {
        alm = ALM(0xDaD4E68a5803cfeb862BBCC7F8D0008de96697D9);
        flashLoanAdapter = IFlashLoanAdapter(0xf37D672dd3425beD81A4232Fe33CA711CF128C96);
        hook = BaseStrategyHook(payable(0xE5Ba808abB259EA81BA33D57A54e705a914498C0));
        lendingAdapter = ILendingAdapter(0xF82AbE97BD7F36474ed86c7359241b15F7b54720);
        oracle = IOracle(0x8FDFf3fAd7D2449eB16F8967c40b17D8d324A45f);
        positionManager = IPositionManagerStandard(0xf7b753380F4D14e6212c8db9dC4b9501EF8c6C6F);
        rebalanceAdapter = SRebalanceAdapter(0x4B7290b91235d89D8329E83f9157C5910EBA169c);
        swapAdapter = ISwapAdapter(0xBa14bA6eCa45E3C3d784D3669ecF25892e5E218b);
    }

    function test_inspect_rebalance() public {
        vm.startPrank(rebalanceAdapter.owner());
        test_inspect_state();
        rebalanceAdapter.rebalance(50000000000000000);
        vm.stopPrank();
    }

    function test_inspect_state() public view {
        console.log("=== SRebalanceAdapter Parameters ===");
        console.log("Weight:", rebalanceAdapter.weight());
        console.log("Long Leverage:", rebalanceAdapter.longLeverage());
        console.log("Short Leverage:", rebalanceAdapter.shortLeverage());
        console.log("Price Threshold:", rebalanceAdapter.rebalancePriceThreshold());
        console.log("Time Threshold:", rebalanceAdapter.rebalanceTimeThreshold());
        console.log("Max Deviation Long:", rebalanceAdapter.maxDeviationLong());
        console.log("Max Deviation Short:", rebalanceAdapter.maxDeviationShort());
        console.log("Is Inverted Assets:", rebalanceAdapter.isInvertedAssets());
        console.log("Is Nova:", rebalanceAdapter.isNova());
        console.log("Rebalance Operator:", rebalanceAdapter.rebalanceOperator());

        console.log("\n=== SRebalanceAdapter State ===");
        console.log("Oracle Price Last Rebalance:", rebalanceAdapter.oraclePriceAtLastRebalance());
        console.log("Sqrt Price Last Rebalance:", rebalanceAdapter.sqrtPriceAtLastRebalance());
        console.log("Time Last Rebalance:", rebalanceAdapter.timeAtLastRebalance());
        console.log("Current Block Timestamp:", block.timestamp);

        console.log("\n=== Oracle Data ===");
        (uint256 currentPrice, uint160 currentSqrtPrice) = oracle.poolPrice();
        console.log("Current Oracle Price:", currentPrice);
        console.log("Current Sqrt Price:", currentSqrtPrice);

        console.log("\n=== Rebalance Check ===");
        (bool needed, uint256 priceThreshold, uint256 triggerTime) = rebalanceAdapter.isRebalanceNeeded(currentPrice);
        console.log("Is Rebalance Needed:", needed);
        console.log("Calculated Price Threshold:", priceThreshold);

        // Price Difference %
        // uint256 priceDiffPercent = priceThreshold > 1e18
        //     ? ((priceThreshold - 1e18) * 100) / 1e18
        //     : ((1e18 - priceThreshold) * 100) / 1e18;
        uint256 diffScaled = priceThreshold > 1e18 ? priceThreshold - 1e18 : 1e18 - priceThreshold;
        uint256 diffPercent = (diffScaled * 100) / 1e18;
        uint256 diffBps = (diffScaled * 10000) / 1e18;
        console.log("Price Difference (%):", diffPercent);
        console.log("Price Difference (BPS):", diffBps);

        console.log("Trigger Time:", triggerTime);

        // Time Difference
        uint256 timeLast = rebalanceAdapter.timeAtLastRebalance();
        if (block.timestamp >= timeLast) {
            uint256 timeDiffSeconds = block.timestamp - timeLast;
            uint256 timeDiffMinutes = timeDiffSeconds / 60;
            console.log("Time Since Last Rebalance (minutes):", timeDiffMinutes);
        } else {
            console.log("Time Since Last Rebalance (minutes): negative?");
        }

        console.log("\n=== Lending Position ===");
        (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();
        console.log("Collateral Long:", CL);
        console.log("Collateral Short:", CS);
        console.log("Debt Long:", DL);
        console.log("Debt Short:", DS);
    }

    // ** Helpers
    function swapETH_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return swapAndReturnDeltas(true, true, amount);
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
