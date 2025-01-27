// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// ** v4 imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";

// ** libraries
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {ErrorsLib} from "@forks/morpho/libraries/ErrorsLib.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {AaveLendingAdapter} from "@src/core/lendingAdapters/AaveLendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

contract ALMGeneralTest is ALMTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using TokenWrapperLib for uint256;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);

        initialSQRTPrice = getPoolSQRTPrice(ALMBaseLib.ETH_USDC_POOL); // 3843 usdc for eth (but in reversed tokens order)

        deployFreshManagerAndRouters();

        create_accounts_and_tokens();
        init_hook(address(USDC), address(WETH), 6, 18);
        approve_accounts();
        presetChainlinkOracles();
    }

    function test_hook_deployment_exploit_revert() public {
        vm.expectRevert();
        (key, ) = initPool(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            hook,
            poolFee + 1, //TODO: check this again. Is fee +1 prove this test case?
            initialSQRTPrice
        );
    }

    function test_aave_lending_adapter_long() public {
        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        IBase(address(lendingAdapter)).setComponents(alice.addr, alice.addr, alice.addr, alice.addr, alice.addr);

        // ** Approve to Morpho
        vm.startPrank(alice.addr);
        WETH.approve(address(lendingAdapter), type(uint256).max);
        USDC.approve(address(lendingAdapter), type(uint256).max);

        // ** Add collateral
        uint256 wethToSupply = 1e18;
        deal(address(WETH), address(alice.addr), wethToSupply);
        lendingAdapter.addCollateralLong(wethToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Borrow
        uint256 usdcToBorrow = ((wethToSupply * 3843) / 1e12) / 2;
        lendingAdapter.borrowLong(c6to18(usdcToBorrow));
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), c6to18(usdcToBorrow), 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToBorrow);

        // ** Repay
        lendingAdapter.repayLong(c6to18(usdcToBorrow));
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Remove collateral
        lendingAdapter.removeCollateralLong(wethToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceState(alice.addr, wethToSupply, 0);

        vm.stopPrank();
    }

    function test_aave_lending_adapter_short() public {
        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        IBase(address(lendingAdapter)).setComponents(alice.addr, alice.addr, alice.addr, alice.addr, alice.addr);

        // ** Approve to LA
        vm.startPrank(alice.addr);
        WETH.approve(address(lendingAdapter), type(uint256).max);
        USDC.approve(address(lendingAdapter), type(uint256).max);

        // ** Add collateral
        uint256 usdcToSupply = 3843 * 1e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.addCollateralShort(c6to18(usdcToSupply));
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Borrow
        uint256 wethToBorrow = ((usdcToSupply * 1e12) / 3843) / 2;
        lendingAdapter.borrowShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), wethToBorrow, 1e1);
        assertEqBalanceState(alice.addr, wethToBorrow, 0);

        // ** Repay
        lendingAdapter.repayShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Remove collateral
        lendingAdapter.removeCollateralShort(c6to18(usdcToSupply));
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToSupply);

        vm.stopPrank();
    }

    function test_accessability() public {
        vm.expectRevert(SafeCallback.NotPoolManager.selector);
        hook.afterInitialize(address(0), key, 0, 0);

        vm.expectRevert(IALM.AddLiquidityThroughHook.selector);
        hook.beforeAddLiquidity(address(0), key, IPoolManager.ModifyLiquidityParams(0, 0, 0, ""), "");

        PoolKey memory failedKey = key;
        failedKey.tickSpacing = 3;

        vm.expectRevert(IALM.UnauthorizedPool.selector);
        hook.beforeAddLiquidity(address(0), failedKey, IPoolManager.ModifyLiquidityParams(0, 0, 0, ""), "");

        vm.expectRevert(SafeCallback.NotPoolManager.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");

        vm.expectRevert(IALM.UnauthorizedPool.selector);
        hook.beforeSwap(address(0), failedKey, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_pause() public {
        vm.prank(deployer.addr);
        hook.setPaused(true);

        vm.expectRevert(IALM.ContractPaused.selector);
        hook.deposit(address(0), 0);

        vm.expectRevert(IALM.ContractPaused.selector);
        hook.withdraw(deployer.addr, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(IALM.ContractPaused.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_shutdown() public {
        vm.prank(deployer.addr);
        hook.setShutdown(true);

        vm.expectRevert(IALM.ContractShutdown.selector);
        hook.deposit(deployer.addr, 0);

        vm.prank(address(manager));
        vm.expectRevert(IALM.ContractShutdown.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_decimals_conversion() public {
        //TODO: add more tests
        uint256 amount = 100 * 1e6;
        assertEq(amount.wrap(6), 100 * 1e18, "1");
        assertEq(amount.wrap(6).unwrap(6), amount, "2");

        amount = 100 * 1e18;
        assertEq(amount.wrap(18), amount, "3");
    }
}
