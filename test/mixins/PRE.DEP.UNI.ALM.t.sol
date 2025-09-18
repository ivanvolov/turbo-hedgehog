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
import {IOracleTest} from "@test/interfaces/IOracleTest.sol";
import {IPositionManagerStandard} from "@test/interfaces/IPositionManagerStandard.sol";

contract PRE_DEPOSIT_UNI_ALMTest is ALMTestBaseUnichain {
    uint256 longLeverage = 3e18;
    uint256 shortLeverage = 2e18;
    uint256 weight = 55e16; //50%
    uint256 liquidityMultiplier = 2e18;
    uint256 slippage = 15e14; //0.15%
    uint24 feeLP = 500; //0.05%

    IERC20 WETH = IERC20(UConstants.WETH);
    IERC20 USDC = IERC20(UConstants.USDC);

    address deployerAddress;

    function setUp() public {
        select_unichain_fork(27301634);

        // ** Setting up test environments params
        {
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
            IS_NTS = true;
        }

        manager = UConstants.manager;
        universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER;

        create_accounts_and_tokens(UConstants.USDC, 6, "USDC", UConstants.WETH, 18, "WETH");

        alm = ALM(0x257C54AB34BD745Fea8bb06eeAb93D4C2D3355c9);
        rebalanceAdapter = SRebalanceAdapter(0xAed8CeB0FeC91fBBf3bfC1Ca779C70d7828c598B);
        hook = BaseStrategyHook(payable(0xab39798bb0a9907B1A76E577A392B56117A358C0));

        flashLoanAdapter = IFlashLoanAdapter(0xB97Ae60106E02939835466b473186A4832A32A32);
        lendingAdapter = ILendingAdapter(0x05E93f708ca58D62617d5e5ad1E6D4a88C8fbcCE);
        oracle = IOracle(0x21e0E87467A9629b35FaB45734d7E0a645931f09);
        positionManager = IPositionManagerStandard(0x721b5752b8215486C1a75bF372f71aCa167480F9);

        deployerAddress = alm.owner();
    }

    uint256 amountToDep = 100 ether;

    function test_deposit() public {
        vm.skip(true);
        assertEq(calcTVL(), 0, "TVL");
        assertEq(hook.liquidity(), 0, "liquidity");

        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);

        uint256 shares = alm.deposit(alice.addr, amountToDep, 0);

        assertApproxEqAbs(shares, amountToDep, 1e1);
        assertEq(alm.balanceOf(alice.addr), shares, "shares on user");
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
        assertEqBalanceStateZero(address(alm));

        assertEqPositionState(amountToDep, 0, 0, 0);
        assertEqProtocolState(initialSQRTPrice, amountToDep);
        assertEq(hook.liquidity(), 0, "liquidity");
    }

    function test_deposit_rebalance() public {
        console.log("oracle.price() %s", oracle.price());
        console.log("totalDecimals %s", IOracleTest(address(oracle)).totalDecDelta());
        console.log("scaleFactor %s", IOracleTest(address(oracle)).scaleFactor());

        amountToDep = 1 ether;
        deal(address(WETH), address(alice.addr), amountToDep);
        vm.prank(alice.addr);
        WETH.approve(address(alm), type(uint256).max);
        vm.prank(alice.addr);
        alm.deposit(alice.addr, amountToDep, 0);

        uint256 preRebalanceTVL = calcTVL();
        console.log("preRebalanceTVL %s", preRebalanceTVL);

        vm.prank(deployerAddress);
        rebalanceAdapter.setRebalanceParams(55e16, 3e18, 2e18);

        vm.prank(deployerAddress);
        rebalanceAdapter.rebalance(15e16);
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
