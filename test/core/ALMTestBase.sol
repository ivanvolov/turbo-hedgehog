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
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {TestLib} from "@test/libraries/TestLib.sol";
import {TickMath as TickMathV3} from "@forks/uniswap-v3/libraries/TickMath.sol";

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
    address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

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

    // --- Shortcuts  --- //

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
            TestLib.getTickSpacingFromFee(poolFee),
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
        WETH = TestERC20(TestLib.WETH);
        vm.label(address(WETH), "WETH");
        USDC = TestERC20(TestLib.USDC);
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
        USDC.approve(address(UNISWAP_V3_ROUTER), type(uint256).max);
        WETH.approve(address(UNISWAP_V3_ROUTER), type(uint256).max);
        vm.stopPrank();
    }

    function alignOraclesAndPools(uint160 newSqrtPrice) public {
        vm.mockCall(
            address(hook.oracle()),
            abi.encodeWithSelector(IOracle.price.selector),
            abi.encode(sqrtPriceToPrice(newSqrtPrice))
        );
        setV3PoolPrice(newSqrtPrice);
    }

    // --- Uniswap V3 --- //

    function getHookPrice() public view returns (uint256) {
        return sqrtPriceToPrice(hook.sqrtPriceCurrent());
    }

    function sqrtPriceToPrice(uint160 sqrtPriceX96) public view returns (uint256) {
        return ALMMathLib.reversePrice(ALMMathLib.getPriceFromSqrtPriceX96(sqrtPriceX96));
    }

    function getV3PoolSQRTPrice(address pool) public view returns (uint160) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        return sqrtPriceX96;
    }

    function getV3PoolPrice(address pool) public view returns (uint256) {
        return ALMMathLib.reversePrice(ALMMathLib.getPriceFromSqrtPriceX96(getV3PoolSQRTPrice(pool)));
    }

    function setV3PoolPrice(uint160 newSqrtPrice) public {
        uint256 targetPrice = sqrtPriceToPrice(newSqrtPrice);

        // ** Configuration parameters
        uint256 initialStepSize = 10000000 ether; // Initial swap amount
        uint256 minStepSize = 0.1 ether; // Minimum swap amount to prevent tiny swaps
        uint256 slippageTolerance = 10e18; // 1% acceptable price difference
        uint256 adaptiveDecayBase = 90; // 90% decay when moving in right direction
        uint256 aggressiveDecayBase = 70; // 70% decay when overshooting

        uint256 currentPrice = getV3PoolPrice(TARGET_SWAP_POOL);
        uint256 previousPrice = currentPrice;
        uint256 stepSize = initialStepSize;

        uint256 iterations = 0;
        while (true) {
            uint256 priceDiff = ALMMathLib.absSub(currentPrice, targetPrice);
            if (priceDiff <= slippageTolerance) break;
            iterations++;

            bool isUsdcToEth = currentPrice < targetPrice;

            // Convert ETH step size to USDC equivalent if needed
            uint256 swapAmount = isUsdcToEth ? (stepSize * currentPrice) / 1e30 : stepSize; // Keep as ETH amount
            _doV3Swap(isUsdcToEth, swapAmount);

            // Get new price and calculate improvement
            previousPrice = currentPrice;
            currentPrice = getV3PoolPrice(TARGET_SWAP_POOL);
            uint256 newPriceDiff = ALMMathLib.absSub(currentPrice, targetPrice);

            // Adaptive step size adjustment
            if (newPriceDiff < priceDiff) {
                // Moving in right direction - gentle decay
                stepSize = (stepSize * adaptiveDecayBase) / 100;
            } else {
                // Overshot or wrong direction - aggressive decay
                stepSize = (stepSize * aggressiveDecayBase) / 100;
            }

            // Ensure minimum step size
            if (stepSize < minStepSize) {
                stepSize = minStepSize;
            }
        }

        console.log("Final price adjustment results:");
        console.log("Target price:", targetPrice);
        console.log("Final price:", currentPrice);
        console.log("iterations:", iterations);
    }

    function _doV3Swap(bool zeroForOne, uint256 amountIn) public returns (uint256 amountOut) {
        deal(zeroForOne ? address(USDC) : address(WETH), address(marketMaker.addr), amountIn);
        vm.startPrank(marketMaker.addr);
        amountOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: zeroForOne ? address(USDC) : address(WETH),
                tokenOut: zeroForOne ? address(WETH) : address(USDC),
                fee: getFeeFromV3Pool(TARGET_SWAP_POOL),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }

    function doV3Swap(bool zeroForOne, uint256 amountIn) public {
        uint256 amountOut = _doV3Swap(zeroForOne, amountIn);
        console.log("%s => %s", amountIn, amountOut);
    }

    function getFeeFromV3Pool(address pool) public view returns (uint24) {
        return IUniswapV3Pool(pool).fee();
    }

    // --- Uniswap V4 --- //

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
        (int256 delta0, int256 delta1) = __swap(zeroForOne, amount, _key);
        return (ALMMathLib.abs(delta0), ALMMathLib.abs(delta1));
    }

    function __swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (int256, int256) {
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
            assertEq(usdcBefore - USDC.balanceOf(swapper.addr), ALMMathLib.abs(delta.amount0()));
            assertEq(WETH.balanceOf(swapper.addr) - wethBefore, ALMMathLib.abs(delta.amount1()));
        } else {
            assertEq(USDC.balanceOf(swapper.addr) - usdcBefore, ALMMathLib.abs(delta.amount0()));
            assertEq(wethBefore - WETH.balanceOf(swapper.addr), ALMMathLib.abs(delta.amount1()));
        }
        return (int256(delta.amount0()), int256(delta.amount1()));
    }

    // --- Custom assertions --- //

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

    function assertEqHookPositionState(
        uint256 preRebalanceTVL,
        uint256 weight,
        uint256 longLeverage,
        uint256 shortLeverage,
        uint256 slippage
    ) public view {
        ILendingAdapter _lendingAdapter = ILendingAdapter(hook.lendingAdapter());

        uint256 calcCL = (preRebalanceTVL * (weight * longLeverage)) / 1e36;
        uint256 calcCS = (((preRebalanceTVL * oracle.price()) / 1e18) * (((1e18 - weight) * shortLeverage) / 1e18)) /
            1e30;
        uint256 calcDL = (((calcCL * oracle.price() * (1e18 - (1e36 / longLeverage))) / 1e36) * (1e18 + slippage)) /
            1e30;
        uint256 calcDS = (((calcCS * (1e18 - (1e36 / shortLeverage)) * 1e18) / oracle.price()) * (1e18 + slippage)) /
            1e24;

        assertApproxEqAbs(calcCL, _lendingAdapter.getCollateralLong(), 1e1);
        assertApproxEqAbs(calcCS, c18to6(_lendingAdapter.getCollateralShort()), 1e1);
        assertApproxEqAbs(calcDL, c18to6(_lendingAdapter.getBorrowedLong()), slippage);
        assertApproxEqAbs(calcDS, _lendingAdapter.getBorrowedShort(), 5 * slippage); //TODO

        assertApproxEqAbs(1e18 - ((hook.TVL() * 1e18) / preRebalanceTVL), slippage, slippage);
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

    // --- Utils --- //

    // ** Convert function: Converts a value with 6 decimals to a representation with 18 decimals
    function c6to18(uint256 amountIn6Decimals) internal pure returns (uint256) {
        return amountIn6Decimals * (10 ** 12);
    }

    // ** Convert function: Converts a value with 18 decimals to a representation with 6 decimals
    function c18to6(uint256 amountIn18Decimals) internal pure returns (uint256) {
        return amountIn18Decimals / (10 ** 12);
    }
}
