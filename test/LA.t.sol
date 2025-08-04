// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {MorphoLendingAdapter} from "@src/core/lendingAdapters/MorphoLendingAdapter.sol";
import {UniswapFlashLoanAdapter} from "@src/core/flashLoanAdapters/UniswapFlashLoanAdapter.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LendingAdaptersTest is ALMTestBase {
    using SafeERC20 for IERC20;

    IERC20 WETH = IERC20(MConstants.WETH);
    IERC20 USDC = IERC20(MConstants.USDC);
    IERC20 USDT = IERC20(MConstants.USDT);

    function setUp() public {
        select_mainnet_fork(22119929);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = MConstants.uniswap_v3_USDC_WETH_POOL;
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
        }
    }

    uint256 _extraQuoteBefore;

    // ----- Flash loan single tests ----- //
    function test_flesh_loan_single_morpho() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_flash_loan_adapter_morpho();
        part_flash_loan_adapter_single();
    }

    function test_flesh_loan_single_morpho_earn() public {
        ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
        ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
        ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
        ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
        ASSERT_EQ_BALANCE_Q_THRESHOLD = 1e1;
        ASSERT_EQ_BALANCE_B_THRESHOLD = 1e1;
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        create_flash_loan_adapter_morpho();
        part_flash_loan_adapter_single();
    }

    function test_flesh_loan_single_euler() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_flash_loan_adapter_euler_USDC_WETH();
        part_flash_loan_adapter_single();
    }

    function test_flesh_loan_single_uniswap() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        vm.prank(deployer.addr);
        flashLoanAdapter = new UniswapFlashLoanAdapter(BASE, QUOTE, MConstants.manager);
        part_flash_loan_adapter_single();
    }

    bytes test_payload;

    function part_flash_loan_adapter_single() public {
        address testAddress = address(this);
        _fakeSetComponents(address(flashLoanAdapter), testAddress);

        // ** Approve to FLA
        QUOTE.forceApprove(address(flashLoanAdapter), type(uint256).max);
        BASE.forceApprove(address(flashLoanAdapter), type(uint256).max);

        test_payload = "0x2";
        _extraQuoteBefore = QUOTE.balanceOf(testAddress);
        assertEqBalanceState(testAddress, _extraQuoteBefore, 0);
        flashLoanAdapter.flashLoanSingle(true, uint256(1000e6), test_payload);
        assertEqBalanceState(testAddress, _extraQuoteBefore, 0);
    }

    function onFlashLoanSingle(bool isBase, uint256 amount, bytes calldata data) public view {
        assertEq(isBase, true, string.concat("token should be ", baseName));
        assertEq(amount, uint256(1000e6), string.concat("amount should be 1000 ", baseName));
        assertEq(data, test_payload, "data should eq");
        assertEqBalanceState(address(this), _extraQuoteBefore, amount);
    }

    // ----- Flash loan two tokens tests ----- //
    function test_flash_loan_two_tokens_morpho() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_flash_loan_adapter_morpho();
        part_flash_loan_two_tokens();
    }

    function test_flash_loan_two_tokens_morpho_earn() public {
        ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
        ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
        ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
        ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
        ASSERT_EQ_BALANCE_Q_THRESHOLD = 1e1;
        ASSERT_EQ_BALANCE_B_THRESHOLD = 1e1;
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        create_flash_loan_adapter_morpho();
        part_flash_loan_two_tokens();
    }

    function test_flash_loan_two_tokens_euler() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_flash_loan_adapter_euler_USDC_WETH();
        part_flash_loan_two_tokens();
    }

    function test_flash_loan_two_tokens_uniswap() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        vm.prank(deployer.addr);
        flashLoanAdapter = new UniswapFlashLoanAdapter(BASE, QUOTE, MConstants.manager);
        part_flash_loan_two_tokens();
    }

    function part_flash_loan_two_tokens() public {
        address testAddress = address(this);
        _fakeSetComponents(address(flashLoanAdapter), testAddress); // ** Enable testAddress to call the adapter

        // ** Approve to FLA
        QUOTE.forceApprove(address(flashLoanAdapter), type(uint256).max);
        BASE.forceApprove(address(flashLoanAdapter), type(uint256).max);

        _extraQuoteBefore = QUOTE.balanceOf(testAddress);
        assertEqBalanceState(testAddress, _extraQuoteBefore, 0);
        test_payload = "0x3";
        flashLoanAdapter.flashLoanTwoTokens(uint256(1000e6), uint256(2000e6), test_payload);
        assertEqBalanceState(testAddress, _extraQuoteBefore, 0);
    }

    function onFlashLoanTwoTokens(uint256 amount0, uint256 amount1, bytes calldata data) public view {
        assertEq(amount0, uint256(1000e6), string.concat("amount should be 1000 ", baseName));
        assertEq(amount1, uint256(2000e6), string.concat("amount should be 100 ", quoteName));
        assertEq(data, test_payload, "data should eq");
        assertEqBalanceState(address(this), _extraQuoteBefore + amount1, amount0);
    }

    // ----- Long tests ----- //
    function test_lending_adapter_long_morpho() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_morpho();
        part_lending_adapter_long();
    }

    function test_lending_adapter_long_euler() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_euler_USDC_WETH();
        part_lending_adapter_long();
    }

    function part_lending_adapter_long() public {
        uint256 expectedPrice = 2652;
        _fakeSetComponents(address(lendingAdapter), alice.addr); // ** Enable Alice to call the adapter

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
        lendingAdapter.borrowLong(usdcToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), usdcToBorrow, 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToBorrow);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Repay
        lendingAdapter.repayLong(usdcToBorrow);
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

    // ----- Short tests ----- //
    function test_lending_adapter_short_morpho() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_morpho();
        part_lending_adapter_short();
    }

    function test_lending_adapter_short_euler() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_euler_USDC_WETH();
        part_lending_adapter_short();
    }

    function part_lending_adapter_short() public {
        uint256 expectedPrice = 2652;
        _fakeSetComponents(address(lendingAdapter), alice.addr); // ** Enable Alice to call the adapter

        // ** Approve to LA
        vm.startPrank(alice.addr);
        WETH.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        // ** Add collateral
        uint256 usdcToSupply = expectedPrice * 1e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.addCollateralShort(usdcToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), usdcToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Borrow
        uint256 wethToBorrow = ((usdcToSupply * 1e12) / expectedPrice) / 4;
        lendingAdapter.borrowShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), usdcToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), wethToBorrow, 1e1);
        assertEqBalanceState(alice.addr, wethToBorrow, 0);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Repay
        lendingAdapter.repayShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), usdcToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Remove collateral
        lendingAdapter.removeCollateralShort(lendingAdapter.getCollateralShort());
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToSupply);
        assertEqBalanceStateZero(address(lendingAdapter));
        vm.stopPrank();
    }

    // ----- In parallel tests ----- //
    function test_lending_adapter_in_parallel_morpho() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_morpho();
        part_lending_adapter_in_parallel();
    }

    function test_lending_adapter_in_parallel_euler() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_euler_USDC_WETH();
        part_lending_adapter_in_parallel();
    }

    function part_lending_adapter_in_parallel() public {
        uint256 expectedPrice = 2652;
        _fakeSetComponents(address(lendingAdapter), alice.addr); // ** Enable Alice to call the adapter

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
        lendingAdapter.addCollateralShort(usdcToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), usdcToSupply, 1e1);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), 0, 1e1);
        assertEqBalanceStateZero(alice.addr);

        // ** Borrow USDC (against WETH)
        uint256 usdcToBorrow = ((wethToSupply * expectedPrice) / 1e12) / 2;
        lendingAdapter.borrowLong(usdcToBorrow);
        assertApproxEqAbs(lendingAdapter.getBorrowedLong(), usdcToBorrow, 1e1);
        assertEqBalanceState(alice.addr, 0, usdcToBorrow);

        // ** Borrow WETH (against USDC)
        uint256 wethToBorrow = ((usdcToSupply * 1e12) / expectedPrice) / 2;
        lendingAdapter.borrowShort(wethToBorrow);
        assertApproxEqAbs(lendingAdapter.getBorrowedShort(), wethToBorrow, 1e1);
        assertEqBalanceState(alice.addr, wethToBorrow, usdcToBorrow);

        // ** Repay USDC Loan
        lendingAdapter.repayLong(usdcToBorrow);
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
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, 1e1);
        assertEqBalanceState(alice.addr, wethToSupply, usdcToSupply);

        vm.stopPrank();
    }

    // ----- Morpho earn tests ----- //
    function test_unicord_morpho_earn_in_borrow_reverts() public {
        ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
        ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
        ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
        ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
        ASSERT_EQ_BALANCE_Q_THRESHOLD = 1e1;
        ASSERT_EQ_BALANCE_B_THRESHOLD = 1e1;
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        create_lending_adapter_morpho_earn();
        _fakeSetComponents(address(lendingAdapter), alice.addr); // ** Enable Alice to call the adapter

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
        ASSERT_EQ_PS_THRESHOLD_CL = 1e1;
        ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
        ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
        ASSERT_EQ_PS_THRESHOLD_DS = 1e1;
        ASSERT_EQ_BALANCE_Q_THRESHOLD = 1e1;
        ASSERT_EQ_BALANCE_B_THRESHOLD = 1e1;
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        create_lending_adapter_morpho_earn();
        _fakeSetComponents(address(lendingAdapter), alice.addr); // ** Enable Alice to call the adapter

        // ** Approve to LA
        vm.startPrank(alice.addr);
        USDT.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        // ** Add Collateral for Long (USDT)
        uint256 usdtToSupply = 1000e6;
        deal(address(USDT), address(alice.addr), usdtToSupply);
        lendingAdapter.addCollateralLong(usdtToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), usdtToSupply, 1e1);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Add Collateral for Short (USDC)
        uint256 usdcToSupply = 1000e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.addCollateralShort(usdcToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), usdcToSupply, 1e1);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        vm.warp(block.timestamp + 1 days);

        // ** Remove USDT Collateral
        lendingAdapter.removeCollateralLong(lendingAdapter.getCollateralLong());
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, 0);
        assertEqBalanceState(alice.addr, usdtToSupply + 95954, 0);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Remove USDC Collateral
        lendingAdapter.removeCollateralShort(lendingAdapter.getCollateralShort());
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, 0);
        assertEqBalanceState(alice.addr, usdtToSupply + 95954, usdcToSupply + 179157);
        assertEqBalanceStateZero(address(lendingAdapter));

        vm.stopPrank();
    }

    function test_unicord_euler_earn_in_parallel() public {
        ASSERT_EQ_BALANCE_Q_THRESHOLD = 1e1;
        ASSERT_EQ_BALANCE_B_THRESHOLD = 1e1;
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_euler_USDC_WETH();
        _fakeSetComponents(address(lendingAdapter), alice.addr); // ** Enable Alice to call the adapter

        // ** Approve to LA
        vm.startPrank(alice.addr);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);
        WETH.forceApprove(address(lendingAdapter), type(uint256).max);

        // ** Add Collateral for Long (WETH)
        uint256 wethToSupply = 1 ether;
        deal(address(WETH), address(alice.addr), wethToSupply);
        lendingAdapter.addCollateralLong(wethToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), wethToSupply, 1e1);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Add Collateral for Short (USDC)
        uint256 usdcToSupply = 1000e6;
        deal(address(USDC), address(alice.addr), usdcToSupply);
        lendingAdapter.addCollateralShort(usdcToSupply);
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), usdcToSupply, 1e1);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(lendingAdapter));

        vm.warp(block.timestamp + 1 days);

        // ** Remove WETH Collateral
        lendingAdapter.removeCollateralLong(lendingAdapter.getCollateralLong());
        assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, 0);
        assertEqBalanceState(alice.addr, wethToSupply + 33893131418418, 0);
        assertEqBalanceStateZero(address(lendingAdapter));

        // ** Remove USDC Collateral
        lendingAdapter.removeCollateralShort(lendingAdapter.getCollateralShort());
        assertApproxEqAbs(lendingAdapter.getCollateralShort(), 0, 0);
        assertEqBalanceState(alice.addr, wethToSupply + 33893131418418, usdcToSupply + 111287);
        assertEqBalanceStateZero(address(lendingAdapter));

        vm.stopPrank();
    }
}
