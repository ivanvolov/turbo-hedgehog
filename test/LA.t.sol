// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";
import {MorphoLendingAdapter} from "@src/core/lendingAdapters/MorphoLendingAdapter.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LendingAdaptersTest is MorphoTestBase {
    using SafeERC20 for IERC20;
    using TokenWrapperLib for uint256;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    IERC20 WETH = IERC20(TestLib.WETH);
    IERC20 USDC = IERC20(TestLib.USDC);
    IERC20 USDT = IERC20(TestLib.USDT);

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
    }

    uint256 _extraQuoteBefore;

    function test_lending_adapter_flash_loan_single_morpho() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_morpho();
        part_lending_adapter_flash_loan_single();
    }

    function test_lending_adapter_flash_loan_single_morpho_earn() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.USDT, 6, "USDT");
        create_lending_adapter_morpho_earn();
        part_lending_adapter_flash_loan_single();
    }

    function test_lending_adapter_flash_loan_single_euler() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        part_lending_adapter_flash_loan_single();
    }

    function part_lending_adapter_flash_loan_single() public {
        address testAddress = address(this);
        _fakeSetComponents(testAddress);

        // ** Approve to LA
        QUOTE.forceApprove(address(lendingAdapter), type(uint256).max);
        BASE.forceApprove(address(lendingAdapter), type(uint256).max);

        _extraQuoteBefore = QUOTE.balanceOf(testAddress);
        assertEqBalanceState(testAddress, _extraQuoteBefore, 0);
        lendingAdapter.flashLoanSingle(address(BASE), uint256(1000e18).unwrap(bDec), "0x2");
        assertEqBalanceState(testAddress, _extraQuoteBefore, 0);
    }

    function onFlashLoanSingle(address token, uint256 amount, bytes calldata data) public view {
        assertEq(token, address(BASE), string.concat("token should be ", baseName));
        assertEq(amount, uint256(1000e18).unwrap(bDec), string.concat("amount should be 1000 ", baseName));
        assertEq(data, "0x2", "data should eq");
        assertEqBalanceState(address(this), _extraQuoteBefore, amount);
    }

    function test_lending_adapter_flash_loan_two_tokens_morpho() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_morpho();
        part_lending_adapter_flash_loan_two_tokens();
    }

    function test_lending_adapter_flash_loan_two_tokens_morpho_earn() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.USDT, 6, "USDT");
        create_lending_adapter_morpho_earn();
        part_lending_adapter_flash_loan_two_tokens();
    }

    function test_lending_adapter_flash_loan_two_tokens_euler() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        part_lending_adapter_flash_loan_two_tokens();
    }

    function part_lending_adapter_flash_loan_two_tokens() public {
        address testAddress = address(this);
        _fakeSetComponents(testAddress); // ** Enable testAddress to call the adapter

        // ** Approve to LA
        QUOTE.forceApprove(address(lendingAdapter), type(uint256).max);
        BASE.forceApprove(address(lendingAdapter), type(uint256).max);

        _extraQuoteBefore = QUOTE.balanceOf(testAddress);
        assertEqBalanceState(testAddress, _extraQuoteBefore, 0);
        lendingAdapter.flashLoanTwoTokens(
            address(BASE),
            uint256(1000e18).unwrap(bDec),
            address(QUOTE),
            uint256(100e18).unwrap(qDec),
            "0x3"
        );
        assertEqBalanceState(testAddress, _extraQuoteBefore, 0);
    }

    function onFlashLoanTwoTokens(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1,
        bytes calldata data
    ) public view {
        assertEq(token0, address(BASE), string.concat("token should be ", baseName));
        assertEq(amount0, uint256(1000e18).unwrap(bDec), string.concat("amount should be 1000 ", baseName));
        assertEq(token1, address(QUOTE), string.concat("token should be ", quoteName));
        assertEq(amount1, uint256(100e18).unwrap(qDec), string.concat("amount should be 100 ", quoteName));
        assertEq(data, "0x3", "data should eq");
        assertEqBalanceState(address(this), _extraQuoteBefore + amount1, amount0);
    }

    function test_lending_adapter_long_morpho() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_morpho();
        part_lending_adapter_long();
    }

    function test_lending_adapter_long_euler() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        part_lending_adapter_long();
    }

    function part_lending_adapter_long() public {
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
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Borrow
        uint256 usdcToBorrow = ((wethToSupply * expectedPrice) / 1e12) / 2;
        lendingAdapter.borrowLong(c6to18(usdcToBorrow));
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), c6to18(usdcToBorrow), 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToBorrow);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Repay
        lendingAdapter.repayLong(c6to18(usdcToBorrow));
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Remove collateral
        lendingAdapter.removeCollateralLong(lendingAdapter.getCollateralLong());
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        assertEqBalanceState(alice.addr, wethToSupply, 0);
        assertEqBalanceStateZero(address(lendingAdapter));
        vm.stopPrank();
    }

    function test_lending_adapter_short_morpho() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_morpho();
        part_lending_adapter_short();
    }

    function test_lending_adapter_short_euler() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        part_lending_adapter_short();
    }

    function part_lending_adapter_short() public {
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
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Borrow
        uint256 wethToBorrow = ((usdcToSupply * 1e12) / expectedPrice) / 4;
        lendingAdapter.borrowShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), c6to18(1e1));
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), wethToBorrow, 1e1);
        assertEqBalanceState(alice.addr, wethToBorrow, 0);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Repay
        lendingAdapter.repayShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), c6to18(1e1));
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Remove collateral
        lendingAdapter.removeCollateralShort(lendingAdapter.getCollateralShort());
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, c6to18(1e1));
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToSupply);
        assertEqBalanceStateZero(address(lendingAdapter));
        vm.stopPrank();
    }

    function test_lending_adapter_in_parallel_morpho() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_morpho();
        part_lending_adapter_in_parallel();
    }

    function test_lending_adapter_in_parallel_euler() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        part_lending_adapter_in_parallel();
    }

    function part_lending_adapter_in_parallel() public {
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
        assertEqBalanceStateZero(alice.addr);

        // ** Add Collateral for Short (USDC)
        uint256 usdcToSupply = expectedPrice * 1e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.addCollateralShort(c6to18(usdcToSupply));
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), c6to18(1e1));
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

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
        assertEqBalanceState(alice.addr, wethToBorrow, 0);

        // ** Repay WETH Loan
        lendingAdapter.repayShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Remove WETH Collateral
        lendingAdapter.removeCollateralLong(lendingAdapter.getCollateralLong());
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, 1e1);
        assertEqBalanceState(alice.addr, wethToSupply, 0);

        // ** Remove USDC Collateral
        lendingAdapter.removeCollateralShort(lendingAdapter.getCollateralShort());
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, c6to18(1e1));
        assertEqBalanceState(alice.addr, wethToSupply, usdcToSupply);

        vm.stopPrank();
    }

    function test_unicord_morpho_earn_in_borrow_reverts() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.USDT, 6, "USDT");
        create_lending_adapter_morpho_earn();
        _fakeSetComponents(alice.addr);

        vm.startPrank(alice.addr);

        vm.expectRevert(MorphoLendingAdapter.NotInBorrowMode.selector);
        lendingAdapter.borrowLong(1e18);

        vm.expectRevert(MorphoLendingAdapter.NotInBorrowMode.selector);
        lendingAdapter.borrowShort(1e18);

        vm.expectRevert(MorphoLendingAdapter.NotInBorrowMode.selector);
        lendingAdapter.repayLong(1e18);

        vm.expectRevert(MorphoLendingAdapter.NotInBorrowMode.selector);
        lendingAdapter.repayShort(1e18);
        vm.stopPrank();
    }

    function test_unicord_morpho_earn_in_parallel() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.USDT, 6, "USDT");
        create_lending_adapter_morpho_earn();
        _fakeSetComponents(alice.addr); // ** Enable Alice to call the adapter

        // ** Approve to LA
        vm.startPrank(alice.addr);
        USDT.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        // ** Add Collateral for Long (USDT)
        uint256 usdtToSupply = 1000e6;
        deal(address(USDT), address(alice.addr), usdtToSupply);
        lendingAdapter.addCollateralLong(c6to18(usdtToSupply));
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), c6to18(usdtToSupply), c6to18(1e1));
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Add Collateral for Short (USDC)
        uint256 usdcToSupply = 1000e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.addCollateralShort(c6to18(usdcToSupply));
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), c6to18(usdcToSupply), c6to18(1e1));
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        //TODO: get fee accumulation check

        // ** Remove USDT Collateral
        lendingAdapter.removeCollateralLong(lendingAdapter.getCollateralLong());
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, c6to18(1e1));
        assertEqBalanceState(alice.addr, usdtToSupply, 0);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Remove USDC Collateral
        lendingAdapter.removeCollateralShort(lendingAdapter.getCollateralShort());
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, c6to18(1e1));
        assertEqBalanceState(alice.addr, usdtToSupply, usdcToSupply);
        assertEqBalanceStateZero(address(lendingAdapter));

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
