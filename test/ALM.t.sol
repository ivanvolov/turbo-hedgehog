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
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ALMGeneralTest is ALMTestBase {
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

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL); // 2652 usdc for eth (but in reversed tokens order)

        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, "USDC", TestLib.WETH, "WETH");
        create_lending_adapter(
            TestLib.eulerUSDCVault1,
            TestLib.eulerWETHVault1,
            TestLib.eulerUSDCVault2,
            TestLib.eulerWETHVault2
        );
        create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC);
        init_hook(6, 18);
        approve_accounts();
    }

    function test_price_conversion_WETH_USDC() public pure {
        uint256 lastRoundPriceWETH = (269760151905 * 1e18) / 1e8;
        uint256 lastRoundPriceUSDC = (99990000 * 1e18) / 1e8;
        uint256 lastRoundPrice = (lastRoundPriceWETH * 1e18) / lastRoundPriceUSDC;

        // ** HRprice to tick
        int24 tick = ALMMathLib.getTickFromPrice(ALMMathLib.getPoolPriceFromOraclePrice(lastRoundPrice, true, 18 - 6));
        assertApproxEqAbs(tick, 197293, 1e2);

        // ** Human readable price (HRprice) to sqrtPrice
        uint160 sqrtPrice = ALMMathLib.getSqrtPriceAtTick(tick);
        assertApproxEqAbs(sqrtPrice, 1523499582928038240140392754132197, 2e30);

        // ** HRprice from tick
        uint256 price = ALMMathLib.getOraclePriceFromPoolPrice(ALMMathLib.getPriceFromTick(197293), true, 18 - 6);
        assertApproxEqAbs(price, lastRoundPrice, TW.wrap(10, 0));
    }

    function test_price_conversion_WETH_USDT() public pure {
        uint256 lastRoundPriceWETH = (269760151905 * 1e18) / 1e8;
        uint256 lastRoundPriceUSDT = (100009255 * 1e18) / 1e8;
        uint256 lastRoundPrice = (lastRoundPriceWETH * 1e18) / lastRoundPriceUSDT;

        // ** HRprice to tick
        int24 tick = ALMMathLib.getTickFromPrice(ALMMathLib.getPoolPriceFromOraclePrice(lastRoundPrice, false, 18 - 6));
        assertApproxEqAbs(tick, -197309, 1e1);

        // ** Human readable price (HRprice) to sqrtPrice
        uint160 sqrtPrice = ALMMathLib.getSqrtPriceAtTick(tick);
        assertApproxEqAbs(sqrtPrice, 4117174797023293996373463, 23e20);

        // ** Tick to HRprice
        console.log(ALMMathLib.getPriceFromTick(-197309));
        uint256 price = ALMMathLib.getOraclePriceFromPoolPrice(ALMMathLib.getPriceFromTick(-197309), false, 18 - 6);
        assertApproxEqAbs(price, lastRoundPrice, 3e18);
    }

    function test_price_conversion_CBBTC_USDC() public pure {
        uint256 lastRoundPriceCBBTC = (9746369236640 * 1e18) / 1e8;
        uint256 lastRoundPriceUSDC = (99990000 * 1e18) / 1e8;
        uint256 lastRoundPrice = (lastRoundPriceCBBTC * 1e18) / lastRoundPriceUSDC;

        // ** HRprice to tick
        int24 tick = ALMMathLib.getTickFromPrice(ALMMathLib.getPoolPriceFromOraclePrice(lastRoundPrice, true, 8 - 6));
        assertApproxEqAbs(tick, -68825, 1e1);

        // ** Human readable price (HRprice) to sqrtPrice
        uint160 sqrtPrice = ALMMathLib.getSqrtPriceAtTick(tick);
        assertApproxEqAbs(sqrtPrice, 2537807876084519460502185164, 2e23);

        // ** HRprice from tick
        uint256 price = ALMMathLib.getOraclePriceFromPoolPrice(ALMMathLib.getPriceFromTick(-68825), true, 8 - 6);
        assertApproxEqAbs(price, lastRoundPrice, 1e1);
    }

    function test_price_conversion_WBTC_USDC() public pure {
        uint256 lastRoundPriceWBTC = (9714669236640 * 1e18) / 1e8;
        uint256 lastRoundPriceUSDC = (99990000 * 1e18) / 1e8;
        uint256 lastRoundPrice = (lastRoundPriceWBTC * 1e18) / lastRoundPriceUSDC;

        // ** HRprice to tick
        int24 tick = ALMMathLib.getTickFromPrice(ALMMathLib.getPoolPriceFromOraclePrice(lastRoundPrice, false, 8 - 6));
        assertApproxEqAbs(tick, 68796, 1e1);

        // ** Human readable price (HRprice) to sqrtPrice
        uint160 sqrtPrice = ALMMathLib.getSqrtPriceAtTick(tick);
        assertApproxEqAbs(sqrtPrice, 2470039624898724190709868109667, 6e26);

        // ** HRprice from tick
        uint256 price = ALMMathLib.getOraclePriceFromPoolPrice(ALMMathLib.getPriceFromTick(68796), false, 8 - 6);
        assertApproxEqAbs(price, lastRoundPrice, 1e1);
    }

    function test_hook_deployment_exploit_revert() public {
        vm.expectRevert();
        (key, ) = initPool(
            Currency.wrap(address(TOKEN0)),
            Currency.wrap(address(TOKEN1)),
            hook,
            poolFee + 1, //TODO: check this again. Is fee +1 prove this test case?
            initialSQRTPrice
        );
    }

    function test_lending_adapter_flash_loan_single() public {
        address testAddress = address(this);
        vm.mockCall(testAddress, abi.encodeWithSelector(IALM.paused.selector), abi.encode(false));

        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        IBase(address(lendingAdapter)).setComponents(
            testAddress,
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr
        );

        // ** Approve to LA
        WETH.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        assertEqBalanceStateZero(testAddress);
        lendingAdapter.flashLoanSingle(address(USDC), 1000 * 1e6, "0x2");
    }

    function onFlashLoanSingle(address token, uint256 amount, bytes calldata data) public view {
        assertEq(token, address(USDC), "token should be USDC");
        assertEq(amount, 1000 * 1e6, "amount should be 1000 USDC");
        assertEq(data, "0x2", "data should eq");
        assertEqBalanceState(address(this), 0, amount);
    }

    function test_oracle() public view {
        assertEq(oracle.price(), 2660 * 1e18, "price should eq");
    }

    function test_lending_adapter_flash_loan_two_tokens() public {
        address testAddress = address(this);
        vm.mockCall(testAddress, abi.encodeWithSelector(IALM.paused.selector), abi.encode(false));

        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        IBase(address(lendingAdapter)).setComponents(
            testAddress,
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr
        );

        // ** Approve to LA
        WETH.forceApprove(address(lendingAdapter), type(uint256).max);
        USDC.forceApprove(address(lendingAdapter), type(uint256).max);

        assertEqBalanceStateZero(testAddress);
        lendingAdapter.flashLoanTwoTokens(address(USDC), 1000 * 1e6, address(WETH), 1 ether, "0x3");
    }

    function onFlashLoanTwoTokens(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1,
        bytes calldata data
    ) public view {
        assertEq(token0, address(USDC), "token should be USDC");
        assertEq(amount0, 1000 * 1e6, "amount should be 1000 USDC");
        assertEq(token1, address(WETH), "token should be WETH");
        assertEq(amount1, 1 ether, "amount should be 1 WETH");
        assertEq(data, "0x3", "data should eq");
        assertEqBalanceState(address(this), amount1, amount0);
    }

    function test_lending_adapter_long() public {
        uint256 expectedPrice = 2652;

        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        IBase(address(lendingAdapter)).setComponents(
            address(hook),
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr
        );

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
        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        IBase(address(lendingAdapter)).setComponents(
            address(hook),
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr
        );

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
        uint256 wethToBorrow = ((usdcToSupply * 1e12) / expectedPrice) / 2;
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

        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        IBase(address(lendingAdapter)).setComponents(
            address(hook),
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr,
            alice.addr
        );

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

    function test_hook_pause() public {
        vm.prank(deployer.addr);
        hook.setPaused(true);

        vm.expectRevert(Base.ContractPaused.selector);
        hook.deposit(address(0), 0);

        vm.expectRevert(Base.ContractPaused.selector);
        hook.withdraw(deployer.addr, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(Base.ContractPaused.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_hook_shutdown() public {
        vm.prank(deployer.addr);
        hook.setShutdown(true);

        vm.expectRevert(Base.ContractShutdown.selector);
        hook.deposit(deployer.addr, 0);

        vm.prank(address(manager));
        vm.expectRevert(Base.ContractShutdown.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_TokenWrapperLib_wrap_unwrap_same_wad() public pure {
        uint256 amount = 1 ether;
        uint8 token_wad = 18;

        uint256 wrapped = TokenWrapperLib.wrap(amount, token_wad);
        assertEq(wrapped, amount, "wrap with same wad should return same amount");

        uint256 unwrapped = TokenWrapperLib.unwrap(wrapped, token_wad);
        assertEq(unwrapped, amount, "unwrap with same wad should return original amount");
    }

    function test_TokenWrapperLib_wrap_higher_wad() public pure {
        uint256 amount = 1 ether;
        uint8 token_wad = 24;

        uint256 wrapped = TokenWrapperLib.wrap(amount, token_wad);
        assertEq(wrapped, amount / (10 ** (token_wad - 18)), "wrap with higher wad should divide correctly");

        uint256 unwrapped = TokenWrapperLib.unwrap(wrapped, token_wad);
        assertEq(unwrapped, amount, "unwrap should return original amount");
    }

    function test_TokenWrapperLib_wrap_lower_wad() public pure {
        uint256 amount = 1 ether;
        uint8 token_wad = 6;

        uint256 wrapped = TokenWrapperLib.wrap(amount, token_wad);
        assertEq(wrapped, amount * (10 ** (18 - token_wad)), "wrap with lower wad should multiply correctly");

        uint256 unwrapped = TokenWrapperLib.unwrap(wrapped, token_wad);
        assertEq(unwrapped, amount, "unwrap should return original amount");
    }

    function test_TokenWrapperLib_wrap_zero_amount() public pure {
        uint256 amount = 0;

        uint8 token_wad_12 = 12;
        uint256 wrapped_12 = TokenWrapperLib.wrap(amount, token_wad_12);
        assertEq(wrapped_12, 0, "wrap of zero with wad 12 should return zero");

        uint256 unwrapped_12 = TokenWrapperLib.unwrap(wrapped_12, token_wad_12);
        assertEq(unwrapped_12, 0, "unwrap of zero with wad 12 should return zero");

        uint8 token_wad_18 = 18;
        uint256 wrapped_18 = TokenWrapperLib.wrap(amount, token_wad_18);
        assertEq(wrapped_18, 0, "wrap of zero with wad 18 should return zero");

        uint256 unwrapped_18 = TokenWrapperLib.unwrap(wrapped_18, token_wad_18);
        assertEq(unwrapped_18, 0, "unwrap of zero with wad 18 should return zero");

        uint8 token_wad_24 = 24;
        uint256 wrapped_24 = TokenWrapperLib.wrap(amount, token_wad_24);
        assertEq(wrapped_24, 0, "wrap of zero with wad 24 should return zero");

        uint256 unwrapped_24 = TokenWrapperLib.unwrap(wrapped_24, token_wad_24);
        assertEq(unwrapped_24, 0, "unwrap of zero with wad 24 should return zero");
    }

    function test_TokenWrapperLib_wrap_unwrap_max_values() public {
        uint256 max_amount = type(uint256).max;

        vm.expectRevert(stdError.arithmeticError);
        TokenWrapperLib.wrap(max_amount, 17);

        uint8 token_wad = 18;
        uint256 wrapped = TokenWrapperLib.wrap(max_amount, token_wad);
        assertEq(wrapped, max_amount, "wrap of max value with same wad should not overflow");

        uint256 unwrapped = TokenWrapperLib.unwrap(wrapped, token_wad);
        assertEq(unwrapped, max_amount, "unwrap should return original max amount");
    }
}
