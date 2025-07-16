// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// ** v4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PRBMath} from "@test/libraries/PRBMath.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {Base} from "@src/core/base/Base.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {ALM} from "@src/ALM.sol";
import {BaseStrategyHook} from "@src/core/base/BaseStrategyHook.sol";

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
        create_flash_loan_adapter_euler_WETH_USDC();
        create_oracle(true, TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC, 1 hours, 10 hours);
        init_hook(false, false, 1e18, 0, type(uint256).max, 3000, 3000, 0);
        approve_accounts();
    }

    //TODO: change here to liquidity function check in different scenarios
    // function test_price_conversion_WETH_USDC() public {
    //     vm.skip(true);
    //     // uint256 lastRoundPriceWETH = (269760151905 * 1e18) / 1e8;
    //     // uint256 lastRoundPriceUSDC = (99990000 * 1e18) / 1e8;
    //     // uint256 lastRoundPrice = (lastRoundPriceWETH * 1e18) / lastRoundPriceUSDC;

    //     // // ** HRprice to tick
    //     // int24 tick = TestLib.getTickFromPrice(ALMMathLib.getPoolPriceFromOraclePrice(lastRoundPrice, true, 18 - 6));
    //     // assertApproxEqAbs(tick, 197293, 1e2);

    //     // // ** Human readable price (HRprice) to sqrtPrice
    //     // uint160 sqrtPrice = ALMMathLib.getSqrtPriceX96FromTick(tick);
    //     // assertApproxEqAbs(sqrtPrice, 1523499582928038240140392754132197, 2e30);

    //     // // ** HRprice from tick
    //     // uint256 price = TestLib.getOraclePriceFromPoolPrice(TestLib.getPriceFromTick(197293), true, 18 - 6);
    //     // assertApproxEqAbs(price, lastRoundPrice, 10);
    // }

    // function test_price_conversion_WETH_USDT() public {
    //     vm.skip(true);
    //     // uint256 lastRoundPriceWETH = (269760151905 * 1e18) / 1e8;
    //     // uint256 lastRoundPriceUSDT = (100009255 * 1e18) / 1e8;
    //     // uint256 lastRoundPrice = (lastRoundPriceWETH * 1e18) / lastRoundPriceUSDT;

    //     // // ** HRprice to tick
    //     // int24 tick = TestLib.getTickFromPrice(ALMMathLib.getPoolPriceFromOraclePrice(lastRoundPrice, false, 18 - 6));
    //     // assertApproxEqAbs(tick, -197309, 1e1);

    //     // // ** Human readable price (HRprice) to sqrtPrice
    //     // uint160 sqrtPrice = ALMMathLib.getSqrtPriceX96FromTick(tick);
    //     // assertApproxEqAbs(sqrtPrice, 4117174797023293996373463, 23e20);

    //     // // ** Tick to HRprice

    //     // uint256 price = TestLib.getOraclePriceFromPoolPrice(TestLib.getPriceFromTick(-197309), false, 18 - 6);
    //     // assertApproxEqAbs(price, lastRoundPrice, 3e18);
    // }

    // function test_liquidity_WETH_USDT() public {
    //     vm.skip(true); // This test should test  new calcLiquidity and not the old
    //     // int24 targetTick = -197309;
    //     // int24 targetLowerTick = targetTick - 3000;
    //     // int24 targetUpperTick = targetTick + 3000;

    //     // uint256 price = TestLib.getOraclePriceFromPoolPrice(TestLib.getPriceFromTick(targetTick), false, 18 - 6);
    //     // uint256 priceUpper = TestLib.getOraclePriceFromPoolPrice(
    //     //     TestLib.getPriceFromTick(targetUpperTick),
    //     //     false,
    //     //     18 - 6
    //     // );
    //     // uint256 priceLower = TestLib.getOraclePriceFromPoolPrice(
    //     //     TestLib.getPriceFromTick(targetLowerTick),
    //     //     false,
    //     //     18 - 6
    //     // );

    //     // uint128 liquidity = uint128(
    //     //     TestLib.getVirtualLiquidity(
    //     //         TestLib.getVirtualValue((100e18 * price) / 1e18, 5e17, 3e18, 2e18),
    //     //         price,
    //     //         priceUpper,
    //     //         priceLower
    //     //     )
    //     // );

    //     // assertApproxEqAbs(liquidity, 46634530208923600, 1e8);
    // }

    // function test_price_conversion_CBBTC_USDC() public {
    //     vm.skip(true);
    //     // uint256 lastRoundPriceCBBTC = (9746369236640 * 1e18) / 1e8;
    //     // uint256 lastRoundPriceUSDC = (99990000 * 1e18) / 1e8;
    //     // uint256 lastRoundPrice = (lastRoundPriceCBBTC * 1e18) / lastRoundPriceUSDC;

    //     // // ** HRprice to tick
    //     // int24 tick = TestLib.getTickFromPrice(ALMMathLib.getPoolPriceFromOraclePrice(lastRoundPrice, true, 8 - 6));
    //     // assertApproxEqAbs(tick, -68825, 1e1);

    //     // // ** Human readable price (HRprice) to sqrtPrice
    //     // uint160 sqrtPrice = ALMMathLib.getSqrtPriceX96FromTick(tick);
    //     // assertApproxEqAbs(sqrtPrice, 2537807876084519460502185164, 2e23);

    //     // // ** HRprice from tick
    //     // uint256 price = TestLib.getOraclePriceFromPoolPrice(TestLib.getPriceFromTick(-68825), true, 8 - 6);
    //     // assertApproxEqAbs(price, lastRoundPrice, 1e18);
    // }

    // function test_liquidity_CBBTC_USDC() public {
    //     vm.skip(true); // This test should test  new calcLiquidity and not the old
    //     // int24 targetTick = -68825;
    //     // int24 targetLowerTick = targetTick + 3000;
    //     // int24 targetUpperTick = targetTick - 3000;

    //     // uint256 price = TestLib.getOraclePriceFromPoolPrice(TestLib.getPriceFromTick(targetTick), true, 8 - 6);
    //     // uint256 priceUpper = TestLib.getOraclePriceFromPoolPrice(
    //     //     TestLib.getPriceFromTick(targetUpperTick),
    //     //     true,
    //     //     8 - 6
    //     // );
    //     // uint256 priceLower = TestLib.getOraclePriceFromPoolPrice(
    //     //     TestLib.getPriceFromTick(targetLowerTick),
    //     //     true,
    //     //     8 - 6
    //     // );

    //     // uint256 VLP = TestLib.getVirtualValue((100e18 * price) / 1e18, 5e17, 3e18, 2e18);

    //     // uint128 liquidity = uint128(TestLib.getVirtualLiquidity(VLP, price, priceUpper, priceLower));

    //     // assertApproxEqAbs(liquidity, 280185113050771000, 1e8);
    // }

    // function test_price_conversion_WBTC_USDC() public {
    //     vm.skip(true);
    //     // uint256 lastRoundPriceWBTC = (9714669236640 * 1e18) / 1e8;
    //     // uint256 lastRoundPriceUSDC = (99990000 * 1e18) / 1e8;
    //     // uint256 lastRoundPrice = (lastRoundPriceWBTC * 1e18) / lastRoundPriceUSDC;

    //     // // ** HRprice to tick
    //     // int24 tick = TestLib.getTickFromPrice(ALMMathLib.getPoolPriceFromOraclePrice(lastRoundPrice, false, 8 - 6));
    //     // assertApproxEqAbs(tick, 68796, 1e1);

    //     // // ** Human readable price (HRprice) to sqrtPrice
    //     // uint160 sqrtPrice = ALMMathLib.getSqrtPriceX96FromTick(tick);
    //     // assertApproxEqAbs(sqrtPrice, 2470039624898724190709868109667, 6e26);

    //     // // ** HRprice from tick
    //     // uint256 price = TestLib.getOraclePriceFromPoolPrice(TestLib.getPriceFromTick(68796), false, 8 - 6);
    //     // assertApproxEqAbs(price, lastRoundPrice, 35e18);
    // }

    // function test_liquidity_WBTC_USDC() public {
    //     vm.skip(true); // This test should test  new calcLiquidity and not the old
    //     // int24 targetTick = 68796;
    //     // int24 targetLowerTick = targetTick - 3000;
    //     // int24 targetUpperTick = targetTick + 3000;

    //     // uint256 price = TestLib.getOraclePriceFromPoolPrice(TestLib.getPriceFromTick(targetTick), false, 8 - 6);
    //     // uint256 priceUpper = TestLib.getOraclePriceFromPoolPrice(
    //     //     TestLib.getPriceFromTick(targetUpperTick),
    //     //     false,
    //     //     8 - 6
    //     // );
    //     // uint256 priceLower = TestLib.getOraclePriceFromPoolPrice(
    //     //     TestLib.getPriceFromTick(targetLowerTick),
    //     //     false,
    //     //     8 - 6
    //     // );

    //     // uint256 VLP = TestLib.getVirtualValue((100e18 * price) / 1e18, 5e17, 3e18, 2e18);
    //     // uint128 liquidity = uint128(TestLib.getVirtualLiquidity(VLP, price, priceUpper, priceLower));

    //     // assertApproxEqAbs(liquidity, 279779159321772000, 1e8);
    // }

    function test_pool_deploy_twice_revert() public {
        (address _token0, address _token1) = getTokensInOrder();
        vm.expectRevert();
        initPool(Currency.wrap(_token0), Currency.wrap(_token1), hook, 100, initialSQRTPrice);

        vm.prank(deployer.addr);
        vm.expectRevert();
        initPool(Currency.wrap(_token0), Currency.wrap(_token1), hook, 100, initialSQRTPrice);
    }

    function test_oracle() public view {
        assertEq(oracle.price(), 2660201351, "price should eq");
    }

    function test_accessability() public {
        // ** not manager revert
        vm.expectRevert(ImmutableState.NotPoolManager.selector);
        hook.afterInitialize(address(0), key, 0, 0);

        // ** not manager revert
        vm.expectRevert(ImmutableState.NotPoolManager.selector);
        hook.beforeSwap(address(0), key, SwapParams(true, 0, 0), "");

        // ** this always revert even with correct manager and pool key
        vm.prank(address(manager));
        vm.expectRevert(IALM.AddLiquidityThroughHook.selector);
        hook.beforeAddLiquidity(address(0), key, ModifyLiquidityParams(0, 0, 0, ""), "");

        PoolKey memory failedKey = key;
        failedKey.tickSpacing = 3;

        // ** reverts on failed key
        vm.prank(address(manager));
        vm.expectRevert(IALM.UnauthorizedPool.selector);
        hook.beforeAddLiquidity(address(0), failedKey, ModifyLiquidityParams(0, 0, 0, ""), "");

        // ** reverts on failed key
        vm.prank(address(manager));
        vm.expectRevert(IALM.UnauthorizedPool.selector);
        hook.beforeSwap(address(0), failedKey, SwapParams(true, 0, 0), "");
    }

    function test_hook_pause() public {
        vm.prank(deployer.addr);
        hook.setStatus(1);

        vm.expectRevert(IBase.ContractNotActive.selector);
        hook.deposit(address(0), 0, 0);

        vm.expectRevert(IBase.ContractPaused.selector);
        hook.withdraw(deployer.addr, 0, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(IBase.ContractNotActive.selector);
        hook.beforeSwap(address(0), key, SwapParams(true, 0, 0), "");
    }

    function test_hook_shutdown_allows_withdraw() public {
        vm.prank(deployer.addr);
        hook.setStatus(2);

        vm.expectRevert(IBase.ContractNotActive.selector);
        hook.deposit(deployer.addr, 0, 0);

        vm.prank(address(manager));
        vm.expectRevert(IBase.ContractNotActive.selector);
        hook.beforeSwap(address(0), key, SwapParams(true, 0, 0), "");

        // This is not ContractsNotActive, so it works
        vm.expectRevert(IALM.NotZeroShares.selector);
        hook.withdraw(deployer.addr, 0, 0, 0);
    }

    function test_Fuzz_setWeight_valid(uint256 weight) public {
        weight = bound(weight, 0, 1e18);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceParams(weight, 1e18, 1e18);
    }

    function test_Fuzz_setWeight_invalid(uint256 weight) public {
        vm.assume(weight > 1e18);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.WeightNotValid.selector);
        rebalanceAdapter.setRebalanceParams(weight, 1e18, 1e18);
    }

    function test_Fuzz_setLongLeverage_valid(uint256 longLeverage) public {
        longLeverage = bound(longLeverage, 0, 5e18);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceParams(1e18, longLeverage, 0);
    }

    function test_Fuzz_setLongLeverage_invalid(uint256 longLeverage) public {
        vm.assume(longLeverage > 5e18);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.LeverageValuesNotValid.selector);
        rebalanceAdapter.setRebalanceParams(1e18, longLeverage, 0);
    }

    function test_Fuzz_setShortLeverage_valid(uint256 shortLeverage) public {
        shortLeverage = bound(shortLeverage, 0, 5e18);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceParams(1e18, 5e18, shortLeverage);
    }

    function test_Fuzz_setShortLeverage_invalid(uint256 shortLeverage) public {
        vm.assume(shortLeverage > 5e18);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.LeverageValuesNotValid.selector);
        rebalanceAdapter.setRebalanceParams(1e18, 5e18, shortLeverage);
    }

    function test_Fuzz_longLeverage_gte_shortLeverage(uint256 longLeverage, uint256 shortLeverage) public {
        longLeverage = bound(longLeverage, 0, 5e18);
        shortLeverage = bound(shortLeverage, 0, longLeverage);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceParams(1e18, longLeverage, shortLeverage);
    }

    function test_Fuzz_longLeverage_lt_shortLeverage(uint256 longLeverage, uint256 shortLeverage) public {
        vm.assume(shortLeverage > longLeverage);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.LeverageValuesNotValid.selector);
        rebalanceAdapter.setRebalanceParams(1e18, longLeverage, shortLeverage);
    }

    function test_Fuzz_setMaxDeviationLong_valid(uint256 maxDevLong) public {
        maxDevLong = bound(maxDevLong, 0, 5e17);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceConstraints(1e18, 1 days, maxDevLong, 0);
    }

    function test_Fuzz_setMaxDeviationLong_invalid(uint256 maxDevLong) public {
        vm.assume(maxDevLong > 5e17);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.MaxDeviationNotValid.selector);
        rebalanceAdapter.setRebalanceConstraints(1e18, 1 days, maxDevLong, 0);
    }

    function test_Fuzz_setMaxDeviationShort_valid(uint256 maxDevShort) public {
        maxDevShort = bound(maxDevShort, 0, 5e17);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceConstraints(1e18, 1 days, 0, maxDevShort);
    }

    function test_Fuzz_setMaxDeviationShort_invalid(uint256 maxDevShort) public {
        vm.assume(maxDevShort > 5e17);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.MaxDeviationNotValid.selector);
        rebalanceAdapter.setRebalanceConstraints(1e18, 1 days, 0, maxDevShort);
    }

    function test_Fuzz_setProtocolFee_valid(uint256 protocolFee) public {
        protocolFee = bound(protocolFee, 0, 3e16);
        vm.prank(deployer.addr);
        hook.setProtocolParams(1e18, protocolFee, 1e18, int24(1e6), int24(1e6), 1e18);
    }

    function test_Fuzz_setProtocolFee_invalid(uint256 protocolFee) public {
        vm.assume(protocolFee > 1e18);
        vm.prank(deployer.addr);
        vm.expectRevert(IALM.ProtocolFeeNotValid.selector);
        hook.setProtocolParams(1e18, protocolFee, 1e18, int24(1e6), int24(1e6), 1e18);
    }

    function test_Fuzz_setLiquidityMultiplier_valid(uint256 liquidityMultiplier) public {
        liquidityMultiplier = bound(liquidityMultiplier, 0, 10e18);
        vm.prank(deployer.addr);
        hook.setProtocolParams(liquidityMultiplier, 0, 1e18, int24(1e6), int24(1e6), 1e18);
    }

    function test_Fuzz_setLiquidityMultiplier_invalid(uint256 liquidityMultiplier) public {
        vm.assume(liquidityMultiplier > 10e18);
        vm.prank(deployer.addr);
        vm.expectRevert(IALM.LiquidityMultiplierNotValid.selector);
        hook.setProtocolParams(liquidityMultiplier, 0, 1e18, int24(1e6), int24(1e6), 1e18);
    }
}
