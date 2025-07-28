// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";
import {ALM} from "@src/ALM.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants} from "@test/libraries/Constants.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiquidityAmounts} from "v4-core-test/utils/LiquidityAmounts.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ALMMathLib} from "../../../src/libraries/ALMMathLib.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IFlashLoanAdapter} from "@src/interfaces/IFlashLoanAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManagerStandard} from "@src/interfaces/IPositionManager.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {ISwapAdapter} from "@src/interfaces/swapAdapters/ISwapAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IOracleTest, IChronicleSelfKisser} from "@test/interfaces/IOracleTest.sol";
import {PathKey} from "v4-periphery/src/interfaces/IV4Router.sol";

contract ETHALM_UNICORDTest is MorphoTestBase {
    using SafeERC20 for IERC20;

    IERC20 WETH = IERC20(Constants.WETH);
    IERC20 USDC = IERC20(Constants.USDC);
    IERC20 USDT = IERC20(Constants.USDT);

    ALM hook1;
    ALM hook2;
    PoolKey USDC_USDT_key;
    PoolKey USDC_WETH_key;

    uint24 feeLP = 500; //0.05%

    uint256 k1 = 1425e15; //1.425
    uint256 k2 = 1425e15; //1.425

    function setUp() public {
        uint256 mainnetFork = vm.createFork(UNICHAIN_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(22789424);

        // ** Setting up test environments params
        {
            assertEqPSThresholdCL = 1e5;
            assertEqPSThresholdCS = 1e1;
            assertEqPSThresholdDL = 1e1;
            assertEqPSThresholdDS = 1e5;
        }

        initialSQRTPrice = SQRT_PRICE_1_1;
        _create_accounts();
        manager = Constants.manager;
        universalRouter = Constants.UNIVERSAL_ROUTER;
    }

    function part_deploy_ETH_ALM() internal {
        uint256 longLeverage = 3e18;
        uint256 shortLeverage = 2e18;
        uint256 weight = 55e16; //50%
        uint256 liquidityMultiplier = 2e18;
        BASE = USDC;
        QUOTE = WETH;

        create_lending_adapter_euler_WETH_USDC_unichain();
        create_flash_loan_adapter_morpho_unichain();
        oracle = _create_oracle(
            AggregatorV3Interface(0x152598809FB59db55cA76f89a192Fb23555531D8), // WETH
            AggregatorV3Interface(0x5e9Aae684047a0ACf2229fAefE8b46726335CE77), // USDC
            24 hours,
            24 hours,
            true,
            int8(6 - 18)
        );
        mock_latestRoundData(0x152598809FB59db55cA76f89a192Fb23555531D8, 3732706458000000000000);
        mock_latestRoundData(0x5e9Aae684047a0ACf2229fAefE8b46726335CE77, 1000010000000000000);

        production_init_hook(false, false, liquidityMultiplier, 0, 1000 ether, 3000, 3000, TestLib.sqrt_price_10per);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            // hook.setNextLPFee(0); // By default, dynamic-fee-pools initialize with a 0% fee, to change - call rebalance.
            IPositionManagerStandard(address(positionManager)).setKParams(1425 * 1e15, 1425 * 1e15); // 1.425 1.425
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(TestLib.ONE_PERCENT_AND_ONE_BPS, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }
        hook2 = hook;
        USDC_WETH_key = key;
    }

    function part_deploy_UNICORD() internal {
        uint256 longLeverage = 1e18;
        uint256 shortLeverage = 1e18;
        uint256 weight = 50e16; //50%
        uint256 liquidityMultiplier = 1e18;
        BASE = USDC;
        QUOTE = USDT;

        create_lending_adapter_euler_USDC_USDT_unichain();
        create_flash_loan_adapter_morpho_unichain();
        oracle = _create_oracle(
            AggregatorV3Interface(0x8E947Ea7D5881Cd600Ace95F1201825F8C708844), // USDT
            AggregatorV3Interface(0x5e9Aae684047a0ACf2229fAefE8b46726335CE77), // USDC
            24 hours,
            24 hours,
            true,
            int8(0)
        );
        mock_latestRoundData(0x8E947Ea7D5881Cd600Ace95F1201825F8C708844, 1000535721908032161);
        mock_latestRoundData(0x5e9Aae684047a0ACf2229fAefE8b46726335CE77, 1000010000000000000);

        production_init_hook(false, true, liquidityMultiplier, 0, 1000000 ether, 100, 100, type(uint256).max);

        // ** Setting up strategy params
        {
            vm.startPrank(deployer.addr);
            hook.setTreasury(treasury.addr);
            rebalanceAdapter.setRebalanceParams(weight, longLeverage, shortLeverage);
            rebalanceAdapter.setRebalanceConstraints(2, 2000, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
            vm.stopPrank();
        }
        hook1 = hook;
        USDC_USDT_key = key;
    }

    uint256 amountToDep1 = 1e12; //1M USDC

    function part_deposit_UNICORD() public {
        deal(address(USDT), address(alice.addr), amountToDep1);

        vm.startPrank(alice.addr);
        USDT.approve(address(hook), type(uint256).max);
        uint256 shares = hook.deposit(alice.addr, amountToDep1, 0);
        vm.stopPrank();

        assertApproxEqAbs(shares, amountToDep1, 1);
        assertEqBalanceStateZero(alice.addr);
    }

    uint256 amountToDep2 = 100 ether;

    function part_deposit_ETHALM() public {
        deal(address(WETH), address(alice.addr), amountToDep2);
        vm.startPrank(alice.addr);
        WETH.approve(address(hook), type(uint256).max);
        uint256 shares = hook.deposit(alice.addr, amountToDep2, 0);
        vm.stopPrank();

        assertApproxEqAbs(shares, amountToDep2, 1);
        assertEqBalanceStateZero(alice.addr);
    }

    function part_rebalance_UNICORD() public {
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(10e14);
    }

    function part_rebalance_ETH_ALM() public {
        vm.prank(deployer.addr);
        rebalanceAdapter.rebalance(10e14);
    }

    function par_swap_up_in_ETH_ALM() public {
        vm.startPrank(swapper.addr);
        USDC.forceApprove(address(Constants.PERMIT_2), type(uint256).max);
        Constants.PERMIT_2.approve(address(USDC), address(universalRouter), type(uint160).max, type(uint48).max);

        WETH.forceApprove(address(Constants.PERMIT_2), type(uint256).max);
        Constants.PERMIT_2.approve(address(WETH), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        uint256 testFee = (uint256(feeLP) * 1e30) / 1e18;

        // ** Swap Up In
        {
            uint256 usdcToSwap = 1000e6; // 100k USDC
            deal(address(USDC), address(swapper.addr), usdcToSwap);

            uint160 preSqrtPrice = hook.sqrtPriceCurrent();
            (uint256 deltaUSDC, uint256 deltaWETH) = swapUSDC_WETH_In(usdcToSwap);

            (uint256 deltaX, uint256 deltaY) = _checkSwap(hook.liquidity(), preSqrtPrice, hook.sqrtPriceCurrent());

            console.log("deltaUSDC %s", deltaUSDC);
            console.log("deltaWETH %s", deltaWETH);
            console.log("deltaX %s", deltaX);
            console.log("deltaY %s", deltaY);

            // assertApproxEqAbs(deltaWETH, deltaX, 2);
            // assertApproxEqAbs((deltaUSDC * (1e18 - testFee)) / 1e18, deltaY, 4);
        }
    }

    function test_lifecycle() public {
        part_deploy_UNICORD();

        {
            PoolKey memory _USDC_USDT_key_v2 = _getAndCheckPoolKey(
                USDC,
                USDT,
                100,
                1,
                0x77ea9d2be50eb3e82b62db928a1bcc573064dd2a14f5026847e755518c8659c9
            );

            vm.startPrank(deployer.addr);
            setSwapAdapterToV4SingleSwap(_USDC_USDT_key_v2, true);
            vm.stopPrank();
        }

        part_deposit_UNICORD();
        part_rebalance_UNICORD();

        part_deploy_ETH_ALM();

        //USDC->USDT->ETH->WETH
        {
            PoolKey memory ETH_USDT_key = _getAndCheckPoolKey(
                IERC20(0x8f187aA05619a017077f5308904739877ce9eA21),
                USDT,
                500,
                10,
                0xb04f843bc757e90d9115ed4720eec7d8bcd68052f7cec657f18ed8e6a2001211
            );
            PathKey[] memory path = new PathKey[](2);
            path[0] = PathKey(
                USDC_USDT_key.currency0,
                USDC_USDT_key.fee,
                USDC_USDT_key.tickSpacing,
                USDC_USDT_key.hooks,
                abi.encodePacked(uint8(1))
            );
            path[1] = PathKey(
                ETH_USDT_key.currency1,
                ETH_USDT_key.fee,
                ETH_USDT_key.tickSpacing,
                ETH_USDT_key.hooks,
                abi.encodePacked(uint8(2))
            );

            vm.startPrank(deployer.addr);
            setSwapAdapterToV4MultihopSwap(abi.encode(true, path), false);
            vm.stopPrank();
        }

        part_deposit_ETHALM();

        part_rebalance_ETH_ALM();
        console.log("REBALANCE DONE");

        vm.startPrank(deployer.addr);
        rebalanceAdapter.setRebalanceConstraints(1e15, 60 * 60 * 24 * 7, 1e17, 1e17); // 0.1 (1%), 0.1 (1%)
        hook.setNextLPFee(feeLP);
        vm.stopPrank();

        par_swap_up_in_ETH_ALM();
    }

    // ** Helpers

    // function swapWETH_USDC_Out(uint256 amount) public returns (uint256, uint256) {
    //     return _swap(false, int256(amount), key);
    // }

    // function quoteWETH_USDC_Out(uint256 amount) public returns (uint256) {
    //     return _quoteOutputSwap(false, amount);
    // }

    // function swapWETH_USDC_In(uint256 amount) public returns (uint256, uint256) {
    //     return _swap(false, -int256(amount), key);
    // }

    // function swapUSDC_WETH_Out(uint256 amount) public returns (uint256, uint256) {
    //     return _swap(true, int256(amount), key);
    // }

    // function quoteUSDC_WETH_Out(uint256 amount) public returns (uint256) {
    //     return _quoteOutputSwap(true, amount);
    // }

    function swapUSDC_WETH_In(uint256 amount) public returns (uint256, uint256) {
        int256 usdcBefore = int256(USDC.balanceOf(swapper.addr));
        int256 wethBefore = int256(WETH.balanceOf(swapper.addr));
        __swap_production(true, true, amount, USDC_WETH_key);
        int256 usdcAfter = int256(USDC.balanceOf(swapper.addr));
        int256 wethAfter = int256(WETH.balanceOf(swapper.addr));
        return (abs(usdcAfter - usdcBefore), abs(wethAfter - wethBefore));
    }
}
