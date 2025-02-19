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
import {TestERC20} from "v4-core/test/TestERC20.sol";

// ** libraries
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {TokenWrapperLib as TW} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LendingAdaptersTest is MorphoTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    IERC20 WETH = IERC20(TestLib.WETH);
    IERC20 USDC = IERC20(TestLib.USDC);

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = TestLib.uniswap_v3_WETH_USDC_POOL;
            assertEqPSThresholdCL = 1e5;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e5;
        }
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        // create_lending_adapter_euler(
        //     TestLib.eulerUSDCVault1,
        //     0,
        //     TestLib.eulerWETHVault1,
        //     0,
        //     TestLib.eulerUSDCVault2,
        //     0,
        //     TestLib.eulerWETHVault2,
        //     0
        // );
        create_lending_adapter_morpho();
    }

    uint256 _extraWethBefore;

    function test_lending_adapter_flash_loan_single() public {
        address testAddress = address(this);
        _fakeSetComponents(testAddress); // ** Enable testAddress to call the adapter

        // ** Approve to LA
        WETH.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        _extraWethBefore = WETH.balanceOf(testAddress);
        assertEqBalanceState(testAddress, _extraWethBefore, 0);
        lendingAdapter.flashLoanSingle(address(USDC), 1000 * 1e6, "0x2");
    }

    function onFlashLoanSingle(address token, uint256 amount, bytes calldata data) public view {
        console.log("> onFlashLoanSingle");
        assertEq(token, address(USDC), "token should be USDC");
        assertEq(amount, 1000 * 1e6, "amount should be 1000 USDC");
        assertEq(data, "0x2", "data should eq");
        assertEqBalanceState(address(this), _extraWethBefore, amount);
    }

    function test_lending_adapter_flash_loan_two_tokens() public {
        address testAddress = address(this);
        _fakeSetComponents(testAddress); // ** Enable testAddress to call the adapter

        // ** Approve to LA
        WETH.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        _extraWethBefore = WETH.balanceOf(testAddress);
        assertEqBalanceState(testAddress, _extraWethBefore, 0);
        lendingAdapter.flashLoanTwoTokens(address(USDC), 1000 * 1e6, address(WETH), 1 ether, "0x3");
    }

    function onFlashLoanTwoTokens(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1,
        bytes calldata data
    ) public view {
        console.log("> onFlashLoanTwoTokens");
        assertEq(token0, address(USDC), "token should be USDC");
        assertEq(amount0, 1000 * 1e6, "amount should be 1000 USDC");
        assertEq(token1, address(WETH), "token should be WETH");
        assertEq(amount1, 1 ether, "amount should be 1 WETH");
        assertEq(data, "0x3", "data should eq");
        assertEqBalanceState(address(this), _extraWethBefore + amount1, amount0);
    }

    function test_lending_adapter_long() public {
        uint256 expectedPrice = 2652;
        _fakeSetComponents(alice.addr); // ** Enable Alice to call the adapter

        // ** Approve to LA
        vm.startPrank(alice.addr);
        WETH.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        // ** Add collateral
        uint256 wethToSupply = 1e18;
        deal(address(WETH), address(alice.addr), wethToSupply);
        lendingAdapter.addCollateralLong(wethToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Borrow
        uint256 usdcToBorrow = ((wethToSupply * expectedPrice) / 1e12) / 2;
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
        lendingAdapter.removeCollateralLong(lendingAdapter.getCollateralLong());
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceState(alice.addr, wethToSupply, 0);

        vm.stopPrank();
    }

    function test_lending_adapter_short() public {
        uint256 expectedPrice = 2652;
        _fakeSetComponents(alice.addr); // ** Enable Alice to call the adapter

        // ** Approve to LA
        vm.startPrank(alice.addr);
        WETH.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        // ** Add collateral
        uint256 usdcToSupply = expectedPrice * 1e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.addCollateralShort(c6to18(usdcToSupply));
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), c6to18(1e1));
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Borrow
        uint256 wethToBorrow = ((usdcToSupply * 1e12) / expectedPrice) / 4;
        lendingAdapter.borrowShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), c6to18(1e1));
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), wethToBorrow, 1e1);
        assertEqBalanceState(alice.addr, wethToBorrow, 0);

        // ** Repay
        lendingAdapter.repayShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), c6to18(1e1));
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Remove collateral
        lendingAdapter.removeCollateralShort(lendingAdapter.getCollateralShort());
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, c6to18(1e1));
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToSupply);

        vm.stopPrank();
    }

    function test_lending_adapter_in_parallel() public {
        uint256 expectedPrice = 2652;
        _fakeSetComponents(alice.addr); // ** Enable Alice to call the adapter

        // ** Approve to LA
        vm.startPrank(alice.addr);
        WETH.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        // ** Add Collateral for Long (WETH)
        uint256 wethToSupply = 1e18;
        deal(address(WETH), address(alice.addr), wethToSupply);
        lendingAdapter.addCollateralLong(wethToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);

        // ** Add Collateral for Short (USDC)
        uint256 usdcToSupply = expectedPrice * 1e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.addCollateralShort(c6to18(usdcToSupply));
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), c6to18(1e1));
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);

        // ** Borrow USDC (against WETH)
        uint256 usdcToBorrow = ((wethToSupply * expectedPrice) / 1e12) / 2;
        lendingAdapter.borrowLong(c6to18(usdcToBorrow));
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), c6to18(usdcToBorrow), 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToBorrow);

        // ** Borrow WETH (against USDC)
        uint256 wethToBorrow = ((usdcToSupply * 1e12) / expectedPrice) / 2;
        lendingAdapter.borrowShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), wethToBorrow, 1e1);
        assertEqBalanceState(alice.addr, wethToBorrow, usdcToBorrow);

        // ** Repay USDC Loan
        lendingAdapter.repayLong(c6to18(usdcToBorrow));
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);

        // ** Repay WETH Loan
        lendingAdapter.repayShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);

        // ** Remove WETH Collateral
        lendingAdapter.removeCollateralLong(lendingAdapter.getCollateralLong());
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, 1e1);

        // ** Remove USDC Collateral
        lendingAdapter.removeCollateralShort(lendingAdapter.getCollateralShort());
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, c6to18(1e1));

        assertEqBalanceState(alice.addr, wethToSupply, usdcToSupply);

        vm.stopPrank();
    }

    // ---- Helpers ----

    function _fakeSetComponents(address fakeHook) internal {
        vm.mockCall(fakeHook, abi.encodeWithSelector(IALM.paused.selector), abi.encode(false));
        vm.mockCall(fakeHook, abi.encodeWithSelector(IALM.shutdown.selector), abi.encode(false));
        vm.prank(deployer.addr);
        _setTokens(address(lendingAdapter));
        vm.prank(deployer.addr);
        IBase(address(lendingAdapter)).setComponents(
            fakeHook,
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr
        );
    }
}
