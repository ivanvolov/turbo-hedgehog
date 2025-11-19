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

contract ARB_ETH_UNI_ALMTest is ALMTestBaseUnichain {
    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16; //55%
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 15e14; //0.15%
    uint24 feeLP = 500; //0.05%

    IERC20 WETH = IERC20(UConstants.WETH);
    IERC20 USDC = IERC20(UConstants.USDC);

    function setUp() public {
        select_unichain_fork(32808606);

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

        part_deploy_new_hook();
        // part_connect_old_hook();
    }

    function part_connect_old_hook() public {
        alm = ALM(0x2C3Db13984A8beda3E010A37AD0EB9d6631909E6);
        flashLoanAdapter = IFlashLoanAdapter(0xe86CBC73306ED4175e9aa17F2335f22F1D378c6D);
        hook = BaseStrategyHook(payable(0xa0854c885D80A2591b081A30F9d0AE9915D518C0));
        lendingAdapter = ILendingAdapter(0x98bEf40722b21382C3389B72F16f9b79CEdA8Db1);
        oracle = IOracle(0xC497f949d484A92d101aD5bab2B246DB826E79eD);
        positionManager = IPositionManagerStandard(0xB15f788e39639a86fb27ea9355C4226FecEbA496);
        rebalanceAdapter = SRebalanceAdapter(0x03Abaf87f1D96d8AA5e6805D63B99DB6162bEdCe);
        swapAdapter = ISwapAdapter(0x266d2B28E6F6D1426cB8380179D0748861168Ec4);
    }

    function part_deploy_new_hook() public {
        create_accounts_and_tokens(UConstants.USDC, 6, "USDC", UConstants.WETH, 18, "WETH");
        create_flash_loan_adapter_morpho_unichain();
        create_lending_adapter_euler_USDC_WETH_unichain();
        create_oracle(UConstants.api3_feed_USDC, UConstants.api3_feed_WETH, false);
        // mock_latestRoundData(UConstants.chronicle_feed_WETH, 3634568623200000000000);
        // mock_latestRoundData(UConstants.chronicle_feed_USDC, 999820000000000000);
        init_hook(false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.SQRT_PRICE_10PER);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
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

        ETH_USDC_key_unichain = _getAndCheckPoolKey(
            ETH,
            IERC20(UConstants.USDC),
            500,
            10,
            0x3258f413c7a88cda2fa8709a589d221a80f6574f63df5a5b6774485d8acc39d9
        );
    }

    uint256 amountToDep = 28000000000000000; // 100$ in ETH - 3500

    function part_deposit_rebalance() public {
        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        alm.deposit(alice.addr, amountToDep, 0);

        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(slippage);
    }

    function part_swap_price_up_in() public {
        // ** Before swap State
        uint256 usdcToSwap = 10_000 * 1e6;
        deal(address(USDC), address(swapper.addr), usdcToSwap);

        // ** Swap
        swapUSDC_ETH_In(usdcToSwap);
    }

    /// @dev This is needed for composability testing.
    function part_swap_price_down_in() public {
        // ** Before swap State
        uint256 ethToSwap = amountToDep / 10;
        deal(address(swapper.addr), ethToSwap);

        // ** Swap
        swapETH_USDC_In(ethToSwap);
    }

    function test_deposit_rebalance_swap_price_up_out_arbitrage() public {
        part_deposit_rebalance();
        part_swap_price_down_in();
        part_do_arbitrage();
    }

    function test_deposit_rebalance_swap_price_up_in_arbitrage() public {
        vm.skip(true);
        part_deposit_rebalance();
        part_swap_price_up_in();
        part_do_arbitrage();
    }

    function part_do_arbitrage() public {
        vm.startPrank(deployer.addr);

        ArbV4V4 arb = new ArbV4V4(manager);
        arb.setPools(key, ETH_USDC_key_unichain);
        (uint256 ratio, uint160 primarySqrtPrice, uint160 targetSqrtPrice) = arb.calcPriceRatio();

        console.log("ratio              %s", ratio);
        console.log("primarySqrtPrice   %s", primarySqrtPrice);
        console.log("targetSqrtPrice    %s", targetSqrtPrice);

        (bool isZeroForOne, uint256 profit0, uint256 profit1) = arb.align();

        console.log("isZeroForOne       %s", isZeroForOne);
        console.log("profit0            %s", profit0);
        console.log("profit1            %s", profit1);

        (ratio, primarySqrtPrice, targetSqrtPrice) = arb.calcPriceRatio();

        console.log("ratio              %s", ratio);
        console.log("primarySqrtPrice   %s", primarySqrtPrice);
        console.log("targetSqrtPrice    %s", targetSqrtPrice);

        console.log("QUOTE balance        %s", QUOTE.balanceOf(address(arb)));
        console.log("BASE balance         %s", BASE.balanceOf(address(arb)));
        console.log("arb balance          %s", address(arb).balance);

        arb.transfer(QUOTE, QUOTE.balanceOf(address(arb)), deployer.addr);
        arb.transfer(BASE, BASE.balanceOf(address(arb)), deployer.addr);
        arb.transfer(IERC20(address(0)), address(arb).balance, deployer.addr);

        console.log("QUOTE balance        %s", QUOTE.balanceOf(address(arb)));
        console.log("BASE balance         %s", BASE.balanceOf(address(arb)));
        console.log("arb balance          %s", address(arb).balance);

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
