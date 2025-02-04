// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// ** V4 imports
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";
import {Deployers} from "v4-core-test/utils/Deployers.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {AaveLendingAdapter} from "@src/core/lendingAdapters/AaveLendingAdapter.sol";
import {PositionManager} from "@src/core/positionManagers/PositionManager.sol";
import {UniswapV3SwapAdapter} from "@src/core/swapAdapters/UniswapV3SwapAdapter.sol";
import {Oracle} from "@src/core/Oracle.sol";

// ** libraries
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {TickMath as TickMathV3} from "@forks/uniswap-v3/libraries/TickMath.sol";
import {OracleLibrary} from "@forks/uniswap-v3/libraries/OracleLibrary.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {IUniswapV3SwapAdapter} from "@src/interfaces/IUniswapV3SwapAdapter.sol";
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {ISwapRouter} from "@forks/ISwapRouter.sol";
import {IUniswapV3Pool} from "@forks/IUniswapV3Pool.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

abstract contract ALMTestBase is Test, Deployers {
    using TestAccountLib for TestAccount;
    using CurrencyLibrary for Currency;

    uint160 initialSQRTPrice;
    ALM hook;
    uint24 constant poolFee = 100; // It's 2*100/100 = 2 ts. TODO: witch to set in production?
    SRebalanceAdapter rebalanceAdapter;

    address constant TARGET_SWAP_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    TestERC20 USDC;
    TestERC20 WETH;

    ILendingAdapter lendingAdapter;
    IPositionManager positionManager;
    ISwapAdapter swapAdapter;
    IOracle oracle;

    TestAccount deployer;
    TestAccount alice;
    TestAccount migrationContract;
    TestAccount swapper;
    TestAccount marketMaker;
    TestAccount zero;

    uint256 almId;

    function init_hook(address _token0, address _token1, uint8 _token0Dec, uint8 _token1Dec) internal {
        vm.startPrank(deployer.addr);

        // MARK: UniV4 hook deployment process
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo("ALM.sol", abi.encode(manager, "NAME", "SYMBOL"), hookAddress);
        hook = ALM(hookAddress);
        vm.label(address(hook), "hook");
        assertEq(hook.owner(), deployer.addr);
        // MARK END

        // MARK: Deploying modules and setting up parameters
        lendingAdapter = new AaveLendingAdapter();
        positionManager = new PositionManager();
        swapAdapter = new UniswapV3SwapAdapter();
        oracle = new Oracle();
        rebalanceAdapter = new SRebalanceAdapter();

        hook.setTokens(_token0, _token1, _token0Dec, _token1Dec);
        hook.setComponents(
            address(hook),
            address(lendingAdapter),
            address(positionManager),
            address(oracle),
            address(rebalanceAdapter),
            address(swapAdapter)
        );

        IBase(address(lendingAdapter)).setTokens(_token0, _token1, _token0Dec, _token1Dec);
        IBase(address(lendingAdapter)).setComponents(
            address(hook),
            address(lendingAdapter),
            address(positionManager),
            address(oracle),
            address(rebalanceAdapter),
            address(swapAdapter)
        );

        IBase(address(positionManager)).setTokens(_token0, _token1, _token0Dec, _token1Dec);
        IBase(address(positionManager)).setComponents(
            address(hook),
            address(lendingAdapter),
            address(positionManager),
            address(oracle),
            address(rebalanceAdapter),
            address(swapAdapter)
        );

        IBase(address(swapAdapter)).setTokens(_token0, _token1, _token0Dec, _token1Dec);
        IBase(address(swapAdapter)).setComponents(
            address(hook),
            address(lendingAdapter),
            address(positionManager),
            address(oracle),
            address(rebalanceAdapter),
            address(swapAdapter)
        );
        IUniswapV3SwapAdapter(address(swapAdapter)).setTargetPool(TARGET_SWAP_POOL);

        IBase(address(rebalanceAdapter)).setTokens(_token0, _token1, _token0Dec, _token1Dec); // * Notice: tokens should be set first in all contracts
        IBase(address(rebalanceAdapter)).setComponents(
            address(hook),
            address(lendingAdapter),
            address(positionManager),
            address(oracle),
            address(rebalanceAdapter),
            address(swapAdapter)
        );

        rebalanceAdapter.setSqrtPriceAtLastRebalance(initialSQRTPrice);
        rebalanceAdapter.setOraclePriceAtLastRebalance(0);
        rebalanceAdapter.setTimeAtLastRebalance(0);
        // MARK END

        // MARK: Pool deployment
        PoolKey memory _key = PoolKey(
            Currency.wrap(_token0),
            Currency.wrap(_token1),
            poolFee,
            int24((poolFee / 100) * 2),
            hook
        ); // pre-compute key in order to restrict hook to this pool

        hook.setAuthorizedPool(_key);
        (key, ) = initPool(Currency.wrap(_token0), Currency.wrap(_token1), hook, poolFee, initialSQRTPrice);

        assertEq(hook.tickLower(), 193764 + 3000);
        assertEq(hook.tickUpper(), 193764 - 3000);
        // MARK END

        // This is needed in order to simulate proper accounting
        deal(_token0, address(manager), 1000 ether);
        deal(_token1, address(manager), 1000 ether);
        vm.stopPrank();
    }

    function create_accounts_and_tokens() public virtual {
        WETH = TestERC20(ALMBaseLib.WETH);
        vm.label(address(WETH), "WETH");
        USDC = TestERC20(ALMBaseLib.USDC);
        vm.label(address(USDC), "USDC");

        deployer = TestAccountLib.createTestAccount("deployer");
        alice = TestAccountLib.createTestAccount("alice");
        migrationContract = TestAccountLib.createTestAccount("migrationContract");
        swapper = TestAccountLib.createTestAccount("swapper");
        marketMaker = TestAccountLib.createTestAccount("marketMaker");
        zero = TestAccountLib.createTestAccount("zero");
    }

    function approve_accounts() public virtual {
        vm.startPrank(alice.addr);
        USDC.approve(address(hook), type(uint256).max);
        WETH.approve(address(hook), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        USDC.approve(address(swapRouter), type(uint256).max);
        WETH.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(marketMaker.addr);
        USDC.approve(address(0xE592427A0AEce92De3Edee1F18E0157C05861564), type(uint256).max);
        WETH.approve(address(0xE592427A0AEce92De3Edee1F18E0157C05861564), type(uint256).max);
        vm.stopPrank();
    }

    // -- Uniswap V3 -- //

    function getPoolSQRTPrice(address pool) public view returns (uint160) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        return sqrtPriceX96;
    }

    function getHookPrice() public view returns (uint256) {
        return ALMMathLib.reversePrice(ALMMathLib.getPriceFromSqrtPriceX96(hook.sqrtPriceCurrent()));
    }

    function getPoolPrice(address pool) public view returns (uint256) {
        return ALMMathLib.reversePrice(ALMMathLib.getPriceFromSqrtPriceX96(getPoolSQRTPrice(pool)));
    }

    function setPoolPrice(uint160 sqrtPrice, bool _in, uint256 amountIn) public returns (uint160) {
        console.log("sqrtPrice to set    ", sqrtPrice);
        console.log("sqrtPrice before set", getPoolSQRTPrice(TARGET_SWAP_POOL));

        deal(_in ? address(USDC) : address(WETH), address(marketMaker.addr), amountIn);
        vm.startPrank(marketMaker.addr);
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _in ? address(USDC) : address(WETH),
                tokenOut: _in ? address(WETH) : address(USDC),
                fee: 500,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
        console.log("sqrtPrice after set ", getPoolSQRTPrice(TARGET_SWAP_POOL));
    }

    // -- Uniswap V4 -- //

    function swapWETH_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, int256(amount), key);
    }

    function swapWETH_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }

    function swapUSDC_WETH_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, int256(amount), key);
    }

    function swapUSDC_WETH_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, -int256(amount), key);
    }

    function _swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (uint256, uint256) {
        vm.prank(swapper.addr);
        BalanceDelta delta = swapRouter.swap(
            _key,
            IPoolManager.SwapParams(
                zeroForOne,
                amount,
                zeroForOne == true ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        return (uint256(int256(delta.amount0())), uint256(int256(delta.amount1())));
    }

    function __swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (int256, int256) {
        // console.log("> __swap");
        uint256 wethBefore = WETH.balanceOf(swapper.addr);
        uint256 usdcBefore = USDC.balanceOf(swapper.addr);

        vm.prank(swapper.addr);
        BalanceDelta delta = swapRouter.swap(
            _key,
            IPoolManager.SwapParams(
                zeroForOne,
                amount,
                zeroForOne == true ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        if (zeroForOne) {
            assertEq(usdcBefore - USDC.balanceOf(swapper.addr), uint256(int256(-delta.amount0())));
            assertEq(WETH.balanceOf(swapper.addr) - wethBefore, uint256(int256(delta.amount1())));
        } else {
            assertEq(USDC.balanceOf(swapper.addr) - usdcBefore, uint256(int256(delta.amount0())));
            assertEq(wethBefore - WETH.balanceOf(swapper.addr), uint256(int256(-delta.amount1())));
        }
        return (int256(delta.amount0()), int256(delta.amount1()));
    }

    // -- Custom assertions -- //

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0, 0);
    }

    function assertEqBalanceState(address owner, uint256 _balanceWETH, uint256 _balanceUSDC) public view {
        assertEqBalanceState(owner, _balanceWETH, _balanceUSDC, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWETH,
        uint256 _balanceUSDC,
        uint256 _balanceETH
    ) public view {
        assertApproxEqAbs(WETH.balanceOf(owner), _balanceWETH, 1e5, "Balance WETH not equal");
        assertApproxEqAbs(USDC.balanceOf(owner), _balanceUSDC, 1e1, "Balance USDC not equal");
        assertApproxEqAbs(owner.balance, _balanceETH, 1e1, "Balance ETH not equal");
    }

    function assertEqPositionState(uint256 CL, uint256 CS, uint256 DL, uint256 DS) public view {
        ILendingAdapter _lendingAdapter = ILendingAdapter(hook.lendingAdapter()); // @Notice: The LA can change in tests
        try this._assertEqPositionState(CL, CS, DL, DS) {} catch {
            console.log("CL", _lendingAdapter.getCollateralLong());
            console.log("CS", c18to6(_lendingAdapter.getCollateralShort()));
            console.log("DL", c18to6(_lendingAdapter.getBorrowedLong()));
            console.log("DS", _lendingAdapter.getBorrowedShort());
            _assertEqPositionState(CL, CS, DL, DS); // @Notice: this is to throw the error
        }
    }

    function _assertEqPositionState(uint256 CL, uint256 CS, uint256 DL, uint256 DS) public view {
        ILendingAdapter _lendingAdapter = ILendingAdapter(hook.lendingAdapter()); // @Notice: The LA can change in tests
        assertApproxEqAbs(_lendingAdapter.getCollateralLong(), CL, 1e5, "CL not equal");
        assertApproxEqAbs(c18to6(_lendingAdapter.getCollateralShort()), CS, 1e1, "CS not equal");
        assertApproxEqAbs(c18to6(_lendingAdapter.getBorrowedLong()), DL, 1e1, "DL not equal");
        assertApproxEqAbs(_lendingAdapter.getBorrowedShort(), DS, 1e5, "DS not equal");
    }

    // --- Utils ---

    // ** Convert function: Converts a value with 6 decimals to a representation with 18 decimals
    function c6to18(uint256 amountIn6Decimals) internal pure returns (uint256) {
        return amountIn6Decimals * (10 ** 12);
    }

    // ** Convert function: Converts a value with 18 decimals to a representation with 6 decimals
    function c18to6(uint256 amountIn18Decimals) internal pure returns (uint256) {
        return amountIn18Decimals / (10 ** 12);
    }
}
