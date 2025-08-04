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
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {toBalanceDelta} from "v4-core/types/BalanceDelta.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PRBMath} from "@test/libraries/math/PRBMath.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

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

contract General_ALMTest is ALMTestBase {
    using PoolIdLibrary for PoolId;

    IERC20 WETH = IERC20(MConstants.WETH);
    IERC20 USDC = IERC20(MConstants.USDC);

    function setUp() public {
        select_mainnet_fork(21817163);

        // ** Setting up test environments params
        {
            TARGET_SWAP_POOL = MConstants.uniswap_v3_WETH_USDC_POOL;
            ASSERT_EQ_PS_THRESHOLD_CL = 1e5;
            ASSERT_EQ_PS_THRESHOLD_CS = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DL = 1e1;
            ASSERT_EQ_PS_THRESHOLD_DS = 1e5;
        }

        initialSQRTPrice = getV3PoolSQRTPrice(TARGET_SWAP_POOL); // 2652 usdc for eth (but in reversed tokens order)

        deployFreshManagerAndRouters();

        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.WETH, 18, "WETH");
        create_lending_adapter_euler_USDC_WETH();
        create_flash_loan_adapter_euler_USDC_WETH();
        create_oracle(true, MConstants.chainlink_feed_WETH, MConstants.chainlink_feed_USDC, 1 hours, 10 hours);
    }

    /// @dev This test will sometimes need other deploys.
    function _part_init_hook() internal {
        init_hook(false, false, 1e18, 0, type(uint256).max, 3000, 3000, 0);
        approve_accounts();
    }

    function test_pool_deploy_twice_revert() public {
        // ** Deploy hook contract
        {
            vm.startPrank(deployer.addr);

            address payable hookAddress = payable(
                address(
                    uint160(
                        Hooks.BEFORE_SWAP_FLAG |
                            Hooks.AFTER_SWAP_FLAG |
                            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                            Hooks.AFTER_INITIALIZE_FLAG
                    )
                )
            );

            (address currency0, address currency1) = getHookCurrenciesInOrder();
            key = PoolKey(
                Currency.wrap(currency0),
                Currency.wrap(currency1),
                LPFeeLibrary.DYNAMIC_FEE_FLAG,
                1, // The value of tickSpacing doesn't change with dynamic fees, so it does matter.
                IHooks(hookAddress)
            );
            deployCodeTo(
                "ALM.sol",
                abi.encode(key, BASE, QUOTE, isInvertedPool, false, manager, "NAME", "SYMBOL"),
                hookAddress
            );
            hook = ALM(hookAddress);
            vm.label(address(hook), "hook");
            _setComponents(address(hook));
            hook.setProtocolParams(1e18, 0, type(uint256).max, 3000, 3000, 0);
            vm.stopPrank();
        }

        // ** Revert initialized but not owner
        vm.expectRevert(); // OwnableUnauthorizedAccount
        initPool(key.currency0, key.currency1, key.hooks, key.fee, key.tickSpacing, initialSQRTPrice);

        // ** Revert bad poolKey
        vm.prank(deployer.addr);
        vm.expectRevert(); // UnauthorizedPool
        initPool(key.currency0, key.currency1, key.hooks, key.fee, 60, initialSQRTPrice);

        // ** Revert not active
        vm.prank(deployer.addr);
        hook.setStatus(1);

        vm.prank(deployer.addr);
        vm.expectRevert(); // ContractNotActive
        initPool(key.currency0, key.currency1, key.hooks, key.fee, key.tickSpacing, initialSQRTPrice);

        // ** Revert already initialized
        vm.prank(deployer.addr);
        hook.setStatus(0);

        vm.prank(deployer.addr);
        initPool(key.currency0, key.currency1, key.hooks, key.fee, key.tickSpacing, initialSQRTPrice);

        vm.prank(deployer.addr);
        vm.expectRevert(); // PoolAlreadyInitialized
        initPool(key.currency0, key.currency1, key.hooks, key.fee, key.tickSpacing, initialSQRTPrice);
    }

    function test_oracle() public {
        _part_init_hook();
        assertEq(oracle.price(), 2660201350, "price should eq");
    }

    function test_accessability() public {
        _part_init_hook();

        // ** not manager revert
        {
            vm.expectRevert(ImmutableState.NotPoolManager.selector);
            hook.afterInitialize(address(0), key, 0, 0);

            vm.expectRevert(ImmutableState.NotPoolManager.selector);
            hook.beforeSwap(address(0), key, SwapParams(true, 0, 0), "");

            vm.expectRevert(ImmutableState.NotPoolManager.selector);
            hook.afterSwap(address(0), key, SwapParams(true, 0, 0), toBalanceDelta(0, 0), "");

            vm.expectRevert(ImmutableState.NotPoolManager.selector);
            hook.beforeAddLiquidity(address(0), key, ModifyLiquidityParams(0, 0, 0, ""), "");

            vm.expectRevert(ImmutableState.NotPoolManager.selector);
            hook.unlockCallback(bytes(""));
        }

        // ** reverts on failed key
        {
            vm.prank(address(manager));
            vm.expectRevert(IALM.UnauthorizedPool.selector);
            hook.afterInitialize(address(0), unauthorizedKey, 0, 0);

            vm.prank(address(manager));
            vm.expectRevert(IALM.UnauthorizedPool.selector);
            hook.beforeSwap(address(0), unauthorizedKey, SwapParams(true, 0, 0), "");

            vm.prank(address(manager));
            vm.expectRevert(IALM.UnauthorizedPool.selector);
            hook.afterSwap(address(0), unauthorizedKey, SwapParams(true, 0, 0), toBalanceDelta(0, 0), "");

            vm.prank(address(manager));
            vm.expectRevert(IALM.UnauthorizedPool.selector);
            hook.beforeAddLiquidity(address(0), unauthorizedKey, ModifyLiquidityParams(0, 0, 0, ""), "");

            // This doesn't have failed key protection.
            // hook.unlockCallback(bytes(""));
        }

        // ** this always revert even with correct manager and pool key
        vm.prank(address(manager));
        vm.expectRevert(IALM.AddLiquidityThroughHook.selector);
        hook.beforeAddLiquidity(address(0), key, ModifyLiquidityParams(0, 0, 0, ""), "");
    }

    function test_hook_pause() public {
        _part_init_hook();
        vm.prank(deployer.addr);
        hook.setStatus(1);

        // ** Hook
        {
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.deposit(address(0), 0, 0);

            vm.expectRevert(IBase.ContractPaused.selector);
            hook.withdraw(deployer.addr, 0, 0, 0);

            // This is checked in test_pool_deploy_twice_revert because need special setup.
            // hook.afterInitialize(address(0), unauthorizedKey, 0, 0);

            vm.prank(address(manager));
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.beforeSwap(address(0), key, SwapParams(true, 0, 0), "");

            vm.prank(address(manager));
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.afterSwap(address(0), key, SwapParams(true, 0, 0), toBalanceDelta(0, 0), "");

            // This doesn't have activity protection.
            // hook.beforeAddLiquidity(address(0), key, ModifyLiquidityParams(0, 0, 0, ""), "");

            vm.prank(address(manager));
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.unlockCallback(bytes(""));

            vm.expectRevert(IBase.ContractPaused.selector);
            hook.onFlashLoanTwoTokens(0, 0, "");

            vm.expectRevert(IBase.ContractPaused.selector);
            hook.onFlashLoanSingle(true, 0, "");

            vm.prank(address(rebalanceAdapter));
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.updateLiquidityAndBoundaries(0);

            vm.prank(deployer.addr);
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.updateLiquidityAndBoundariesToOracle();
        }
    }

    function test_hook_shutdown() public {
        _part_init_hook();
        vm.prank(deployer.addr);
        hook.setStatus(2);

        // ** Hook
        {
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.deposit(address(0), 0, 0);

            // This is not ContractsNotActive, so it works.
            vm.expectRevert(IALM.NotZeroShares.selector);
            hook.withdraw(deployer.addr, 0, 0, 0);

            // This is checked in test_pool_deploy_twice_revert because need special setup.
            // hook.afterInitialize(address(0), unauthorizedKey, 0, 0);

            vm.prank(address(manager));
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.beforeSwap(address(0), key, SwapParams(true, 0, 0), "");

            vm.prank(address(manager));
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.afterSwap(address(0), key, SwapParams(true, 0, 0), toBalanceDelta(0, 0), "");

            // Thi doesn't have active protection.
            // hook.beforeAddLiquidity(address(0), key, ModifyLiquidityParams(0, 0, 0, ""), "");

            vm.prank(address(manager));
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.unlockCallback(bytes(""));

            // This is not ContractPaused, so it works.
            vm.expectRevert(abi.encodeWithSelector(IBase.NotFlashLoanAdapter.selector, address(this)));
            hook.onFlashLoanTwoTokens(0, 0, "");

            // This is not ContractPaused, so it works.
            vm.expectRevert(abi.encodeWithSelector(IBase.NotFlashLoanAdapter.selector, address(this)));
            hook.onFlashLoanSingle(true, 0, "");

            vm.prank(address(rebalanceAdapter));
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.updateLiquidityAndBoundaries(0);

            vm.prank(deployer.addr);
            vm.expectRevert(IBase.ContractNotActive.selector);
            hook.updateLiquidityAndBoundariesToOracle();
        }
    }

    function test_Fuzz_setWeight_valid(uint256 weight) public {
        _part_init_hook();
        weight = bound(weight, 0, 1e18);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceParams(weight, 1e18, 1e18);
    }

    function test_Fuzz_setWeight_invalid(uint256 weight) public {
        _part_init_hook();
        vm.assume(weight > 1e18);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.WeightNotValid.selector);
        rebalanceAdapter.setRebalanceParams(weight, 1e18, 1e18);
    }

    function test_Fuzz_setLongLeverage_valid(uint256 longLeverage) public {
        _part_init_hook();
        longLeverage = bound(longLeverage, 1e18, 5e18);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceParams(1e18, longLeverage, 1e18);
    }

    function test_Fuzz_setLongLeverage_invalid(uint256 longLeverage) public {
        _part_init_hook();
        vm.assume(longLeverage > 5e18);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.LeverageValuesNotValid.selector);
        rebalanceAdapter.setRebalanceParams(1e18, longLeverage, 1e18);
    }

    function test_Fuzz_setShortLeverage_valid(uint256 shortLeverage) public {
        _part_init_hook();
        shortLeverage = bound(shortLeverage, 1e18, 5e18);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceParams(1e18, 5e18, shortLeverage);
    }

    function test_Fuzz_setShortLeverage_invalid(uint256 shortLeverage) public {
        _part_init_hook();
        vm.assume(shortLeverage > 5e18);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.LeverageValuesNotValid.selector);
        rebalanceAdapter.setRebalanceParams(1e18, 5e18, shortLeverage);
    }

    function test_Fuzz_longLeverage_gte_shortLeverage(uint256 longLeverage, uint256 shortLeverage) public {
        _part_init_hook();
        longLeverage = bound(longLeverage, 1e18, 5e18);
        shortLeverage = bound(shortLeverage, 1e18, longLeverage);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceParams(1e18, longLeverage, shortLeverage);
    }

    function test_Fuzz_longLeverage_lt_shortLeverage(uint256 longLeverage, uint256 shortLeverage) public {
        _part_init_hook();
        vm.assume(shortLeverage > longLeverage);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.LeverageValuesNotValid.selector);
        rebalanceAdapter.setRebalanceParams(1e18, longLeverage, shortLeverage);
    }

    function test_Fuzz_setMaxDeviationLong_valid(uint256 maxDevLong) public {
        _part_init_hook();
        maxDevLong = bound(maxDevLong, 0, 5e17);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceConstraints(1e18, 1 days, maxDevLong, 0);
    }

    function test_Fuzz_setMaxDeviationLong_invalid(uint256 maxDevLong) public {
        _part_init_hook();
        vm.assume(maxDevLong > 5e17);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.MaxDeviationNotValid.selector);
        rebalanceAdapter.setRebalanceConstraints(1e18, 1 days, maxDevLong, 0);
    }

    function test_Fuzz_setMaxDeviationShort_valid(uint256 maxDevShort) public {
        _part_init_hook();
        maxDevShort = bound(maxDevShort, 0, 5e17);
        vm.prank(deployer.addr);
        rebalanceAdapter.setRebalanceConstraints(1e18, 1 days, 0, maxDevShort);
    }

    function test_Fuzz_setMaxDeviationShort_invalid(uint256 maxDevShort) public {
        _part_init_hook();
        vm.assume(maxDevShort > 5e17);
        vm.prank(deployer.addr);
        vm.expectRevert(SRebalanceAdapter.MaxDeviationNotValid.selector);
        rebalanceAdapter.setRebalanceConstraints(1e18, 1 days, 0, maxDevShort);
    }

    function test_Fuzz_setProtocolFee_valid(uint256 protocolFee) public {
        _part_init_hook();
        protocolFee = bound(protocolFee, 0, 3e16);
        vm.prank(deployer.addr);
        hook.setProtocolParams(1e18, protocolFee, 1e18, int24(1e6), int24(1e6), 1e18);
    }

    function test_Fuzz_setProtocolFee_invalid(uint256 protocolFee) public {
        _part_init_hook();
        vm.assume(protocolFee > 1e18);
        vm.prank(deployer.addr);
        vm.expectRevert(IALM.ProtocolFeeNotValid.selector);
        hook.setProtocolParams(1e18, protocolFee, 1e18, int24(1e6), int24(1e6), 1e18);
    }

    function test_Fuzz_setLiquidityMultiplier_valid(uint256 liquidityMultiplier) public {
        _part_init_hook();
        liquidityMultiplier = bound(liquidityMultiplier, 0, 10e18);
        vm.prank(deployer.addr);
        hook.setProtocolParams(liquidityMultiplier, 0, 1e18, int24(1e6), int24(1e6), 1e18);
    }

    function test_Fuzz_setLiquidityMultiplier_invalid(uint256 liquidityMultiplier) public {
        _part_init_hook();
        vm.assume(liquidityMultiplier > 10e18);
        vm.prank(deployer.addr);
        vm.expectRevert(IALM.LiquidityMultiplierNotValid.selector);
        hook.setProtocolParams(liquidityMultiplier, 0, 1e18, int24(1e6), int24(1e6), 1e18);
    }
}
