// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// ** v4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {TokenWrapperLib as TW} from "@src/libraries/TokenWrapperLib.sol";
import {PRBMath} from "@prb-math/PRBMath.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ALMGeneralTest is ALMTestBase {
    using PoolIdLibrary for PoolId;

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

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL); // 2652 usdc for eth (but in reversed tokens order)

        deployFreshManagerAndRouters();

        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC, 1 hours, 10 hours);
        init_hook(true, false, false, 0, type(uint256).max, 3000, 3000, 0);
        approve_accounts();
    }

    // function test_gas_per_function() public {
    //     uint256 gas = gasleft();
    //     uint256 a = PRBMath.mulDiv(2e18, 3e18, 6e18);
    //     console.log("mulDiv18", gas - gasleft());
    //     console.log(a);
    // }

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

        uint256 price = ALMMathLib.getOraclePriceFromPoolPrice(ALMMathLib.getPriceFromTick(-197309), false, 18 - 6);
        assertApproxEqAbs(price, lastRoundPrice, 3e18);
    }

    function test_liquidity_WETH_USDT() public pure {
        int24 targetTick = -197309;
        int24 targetLowerTick = targetTick - 3000;
        int24 targetUpperTick = targetTick + 3000;

        uint256 price = ALMMathLib.getOraclePriceFromPoolPrice(ALMMathLib.getPriceFromTick(targetTick), false, 18 - 6);
        uint256 priceUpper = ALMMathLib.getOraclePriceFromPoolPrice(
            ALMMathLib.getPriceFromTick(targetUpperTick),
            false,
            18 - 6
        );
        uint256 priceLower = ALMMathLib.getOraclePriceFromPoolPrice(
            ALMMathLib.getPriceFromTick(targetLowerTick),
            false,
            18 - 6
        );

        uint128 liquidity = uint128(
            ALMMathLib.getVirtualLiquidity(
                ALMMathLib.getVirtualValue((100e18 * price) / 1e18, 5e17, 3e18, 2e18),
                price,
                priceUpper,
                priceLower
            )
        );

        assertApproxEqAbs(liquidity, 46634530208923600, 1e8);
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
        assertApproxEqAbs(price, lastRoundPrice, 1e18);
    }

    function test_liquidity_CBBTC_USDC() public pure {
        int24 targetTick = -68825;
        int24 targetLowerTick = targetTick + 3000;
        int24 targetUpperTick = targetTick - 3000;

        uint256 price = ALMMathLib.getOraclePriceFromPoolPrice(ALMMathLib.getPriceFromTick(targetTick), true, 8 - 6);
        uint256 priceUpper = ALMMathLib.getOraclePriceFromPoolPrice(
            ALMMathLib.getPriceFromTick(targetUpperTick),
            true,
            8 - 6
        );
        uint256 priceLower = ALMMathLib.getOraclePriceFromPoolPrice(
            ALMMathLib.getPriceFromTick(targetLowerTick),
            true,
            8 - 6
        );

        uint256 VLP = ALMMathLib.getVirtualValue((100e18 * price) / 1e18, 5e17, 3e18, 2e18);

        uint128 liquidity = uint128(ALMMathLib.getVirtualLiquidity(VLP, price, priceUpper, priceLower));

        assertApproxEqAbs(liquidity, 280185113050771000, 1e8);
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
        assertApproxEqAbs(price, lastRoundPrice, 35e18);
    }

    function test_liquidity_WBTC_USDC() public pure {
        int24 targetTick = 68796;
        int24 targetLowerTick = targetTick - 3000;
        int24 targetUpperTick = targetTick + 3000;

        uint256 price = ALMMathLib.getOraclePriceFromPoolPrice(ALMMathLib.getPriceFromTick(targetTick), false, 8 - 6);
        uint256 priceUpper = ALMMathLib.getOraclePriceFromPoolPrice(
            ALMMathLib.getPriceFromTick(targetUpperTick),
            false,
            8 - 6
        );
        uint256 priceLower = ALMMathLib.getOraclePriceFromPoolPrice(
            ALMMathLib.getPriceFromTick(targetLowerTick),
            false,
            8 - 6
        );

        uint256 VLP = ALMMathLib.getVirtualValue((100e18 * price) / 1e18, 5e17, 3e18, 2e18);
        uint128 liquidity = uint128(ALMMathLib.getVirtualLiquidity(VLP, price, priceUpper, priceLower));

        assertApproxEqAbs(liquidity, 279779159321772000, 1e8);
    }

    function test_pool_deploy_twice_revert() public {
        (address _token0, address _token1) = getTokensInOrder();
        vm.expectRevert();
        initPool(Currency.wrap(_token0), Currency.wrap(_token1), hook, poolFee + 1, initialSQRTPrice);

        vm.prank(deployer.addr);
        vm.expectRevert();
        initPool(Currency.wrap(_token0), Currency.wrap(_token1), hook, poolFee + 1, initialSQRTPrice);
    }

    function test_oracle() public view {
        assertEq(oracle.price(), 2660201350640229959005, "price should eq");
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

    function test_accessability() public {
        vm.expectRevert(SafeCallback.NotPoolManager.selector);
        hook.afterInitialize(address(0), key, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(IALM.AddLiquidityThroughHook.selector);
        hook.beforeAddLiquidity(address(0), key, IPoolManager.ModifyLiquidityParams(0, 0, 0, ""), "");

        PoolKey memory failedKey = key;
        failedKey.tickSpacing = 3;

        vm.prank(address(manager));
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

        vm.expectRevert(IBase.ContractPaused.selector);
        hook.deposit(address(0), 0, 0);

        vm.expectRevert(IBase.ContractPaused.selector);
        hook.withdraw(deployer.addr, 0, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(IBase.ContractPaused.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_hook_shutdown() public {
        vm.prank(deployer.addr);
        hook.setShutdown(true);

        vm.expectRevert(IBase.ContractShutdown.selector);
        hook.deposit(deployer.addr, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(IBase.ContractShutdown.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_TokenWrapperLib_wrap_unwrap_same_wad() public pure {
        uint256 amount = 1 ether;
        uint8 token_wad = 18;

        uint256 wrapped = TW.wrap(amount, token_wad);
        assertEq(wrapped, amount, "wrap with same wad should return same amount");

        uint256 unwrapped = TW.unwrap(wrapped, token_wad);
        assertEq(unwrapped, amount, "unwrap with same wad should return original amount");
    }

    function test_TokenWrapperLib_wrap_higher_wad() public pure {
        uint256 amount = 1 ether;
        uint8 token_wad = 24;

        uint256 wrapped = TW.wrap(amount, token_wad);
        assertEq(wrapped, amount / (10 ** (token_wad - 18)), "wrap with higher wad should divide correctly");

        uint256 unwrapped = TW.unwrap(wrapped, token_wad);
        assertEq(unwrapped, amount, "unwrap should return original amount");
    }

    function test_TokenWrapperLib_wrap_lower_wad() public pure {
        uint256 amount = 1 ether;
        uint8 token_wad = 6;

        uint256 wrapped = TW.wrap(amount, token_wad);
        assertEq(wrapped, amount * (10 ** (18 - token_wad)), "wrap with lower wad should multiply correctly");

        uint256 unwrapped = TW.unwrap(wrapped, token_wad);
        assertEq(unwrapped, amount, "unwrap should return original amount");
    }

    function test_TokenWrapperLib_wrap_zero_amount() public pure {
        uint256 amount = 0;

        uint8 token_wad_12 = 12;
        uint256 wrapped_12 = TW.wrap(amount, token_wad_12);
        assertEq(wrapped_12, 0, "wrap of zero with wad 12 should return zero");

        uint256 unwrapped_12 = TW.unwrap(wrapped_12, token_wad_12);
        assertEq(unwrapped_12, 0, "unwrap of zero with wad 12 should return zero");

        uint8 token_wad_18 = 18;
        uint256 wrapped_18 = TW.wrap(amount, token_wad_18);
        assertEq(wrapped_18, 0, "wrap of zero with wad 18 should return zero");

        uint256 unwrapped_18 = TW.unwrap(wrapped_18, token_wad_18);
        assertEq(unwrapped_18, 0, "unwrap of zero with wad 18 should return zero");

        uint8 token_wad_24 = 24;
        uint256 wrapped_24 = TW.wrap(amount, token_wad_24);
        assertEq(wrapped_24, 0, "wrap of zero with wad 24 should return zero");

        uint256 unwrapped_24 = TW.unwrap(wrapped_24, token_wad_24);
        assertEq(unwrapped_24, 0, "unwrap of zero with wad 24 should return zero");
    }

    function test_TokenWrapperLib_wrap_unwrap_max_values() public {
        uint256 max_amount = type(uint256).max;

        vm.expectRevert(stdError.arithmeticError);
        TW.wrap(max_amount, 17);

        uint8 token_wad = 18;
        uint256 wrapped = TW.wrap(max_amount, token_wad);
        assertEq(wrapped, max_amount, "wrap of max value with same wad should not overflow");

        uint256 unwrapped = TW.unwrap(wrapped, token_wad);
        assertEq(unwrapped, max_amount, "unwrap should return original max amount");
    }
}
