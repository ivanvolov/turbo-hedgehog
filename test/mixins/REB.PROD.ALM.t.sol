// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {ALMTestBaseUnichain} from "@test/core/ALMTestBaseUnichain.sol";
import {ArbV4V4} from "@test/periphery/ArbV4V4.sol";
import {ALM} from "@src/ALM.sol";
import {BaseStrategyHook} from "@src/core/base/BaseStrategyHook.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
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
        select_unichain_fork(32849947 - 1);

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
        rebalanceAdapter.rebalance(50000000000000000);
        vm.stopPrank();
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
