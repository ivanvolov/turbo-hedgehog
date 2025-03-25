// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** V4 imports
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@forks/uniswap-v4/PoolSwapTest.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Deployers} from "@forks/uniswap-v4/Deployers.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {PositionManager} from "@src/core/positionManagers/PositionManager.sol";
import {UnicordPositionManager} from "@src/core/positionManagers/UnicordPositionManager.sol";
import {UniswapV3SwapAdapter} from "@src/core/swapAdapters/UniswapV3SwapAdapter.sol";
import {Oracle} from "@src/core/Oracle.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {TokenWrapperLib as TW} from "@src/libraries/TokenWrapperLib.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {IUniswapV3SwapAdapter} from "@src/interfaces/swapAdapters/IUniswapV3SwapAdapter.sol";
import {ISwapRouter} from "@src/interfaces/swapAdapters/ISwapRouter.sol";
import {IUniswapV3Pool} from "@src/interfaces/swapAdapters/IUniswapV3Pool.sol";
import {IEulerVault} from "@src/interfaces/lendingAdapters/IEulerVault.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

abstract contract ALMTestBase is Deployers {
    using TestAccountLib for TestAccount;
    using CurrencyLibrary for Currency;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;

    uint160 initialSQRTPrice;
    ALM hook;
    uint24 constant poolFee = 100; // It's 2*100/100 = 2 ts.
    SRebalanceAdapter rebalanceAdapter;

    address public TARGET_SWAP_POOL = TestLib.uniswap_v3_WETH_USDC_POOL;
    address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    IERC20 BASE;
    IERC20 QUOTE;

    string baseName;
    string quoteName;

    uint8 bDec;
    uint8 qDec;

    bool invertedPool = true;

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

    function create_accounts_and_tokens(
        address _base,
        uint8 _bDec,
        string memory _baseName,
        address _quote,
        uint8 _qDec,
        string memory _quoteName
    ) public virtual {
        BASE = IERC20(_base);
        vm.label(_base, _baseName);
        QUOTE = IERC20(_quote);
        vm.label(_quote, _quoteName);
        baseName = _baseName;
        quoteName = _quoteName;
        bDec = _bDec;
        qDec = _qDec;

        deployer = TestAccountLib.createTestAccount("deployer");
        alice = TestAccountLib.createTestAccount("alice");
        migrationContract = TestAccountLib.createTestAccount("migrationContract");
        swapper = TestAccountLib.createTestAccount("swapper");
        marketMaker = TestAccountLib.createTestAccount("marketMaker");
        zero = TestAccountLib.createTestAccount("zero");
    }

    function create_lending_adapter_euler_WETH_USDC() internal {
        create_lending_adapter_euler(
            TestLib.eulerUSDCVault1,
            0,
            TestLib.eulerWETHVault1,
            0,
            TestLib.eulerUSDCVault2,
            0,
            TestLib.eulerWETHVault2,
            0
        );
    }

    function create_lending_adapter_euler(
        address _vault0,
        uint256 deposit0,
        address _vault1,
        uint256 deposit1,
        address _flVault0,
        uint256 deposit2,
        address _flVault1,
        uint256 deposit3
    ) internal {
        vm.prank(deployer.addr);
        lendingAdapter = new EulerLendingAdapter(_vault0, _vault1, _flVault0, _flVault1);
        _deposit_to_euler(_vault0, deposit0);
        _deposit_to_euler(_vault1, deposit1);
        _deposit_to_euler(_flVault0, deposit2);
        _deposit_to_euler(_flVault1, deposit3);
    }

    function _deposit_to_euler(address _vault, uint256 toSupply) internal {
        if (toSupply == 0) return;
        IEulerVault vault = IEulerVault(_vault);
        address asset = vault.asset();
        deal(asset, address(marketMaker.addr), toSupply);

        vm.startPrank(marketMaker.addr);
        IERC20(asset).forceApprove(_vault, type(uint256).max);
        vault.mint(vault.convertToShares(toSupply), marketMaker.addr);
        vm.stopPrank();
    }

    function create_oracle(address feed0, address feed1) internal {
        vm.prank(deployer.addr);
        oracle = new Oracle(feed0, feed1);
    }

    function init_hook(bool _invertedPool, bool isUnicord, int24 _tickLowerDelta, int24 _tickUpperDelta) internal {
        invertedPool = _invertedPool;
        console.log("v3Pool: initialPrice %s", getV3PoolPrice(TARGET_SWAP_POOL));
        console.log("v3Pool: initialSQRTPrice %s", initialSQRTPrice);
        console.log("v3Pool: initialTick %s", getV3PoolTick(TARGET_SWAP_POOL));
        console.log("oracle: initialPrice %s", oracle.price());
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
        // @Notice: lendingAdapter should already be created
        if (isUnicord) positionManager = new UnicordPositionManager();
        else positionManager = new PositionManager();

        swapAdapter = new UniswapV3SwapAdapter();
        // @Notice: oracle should already be created
        rebalanceAdapter = new SRebalanceAdapter();

        _setTokens(address(hook)); // * Notice: tokens should be set first in all contracts
        hook.setIsInvertedPool(invertedPool);
        hook.setTickUpperDelta(_tickUpperDelta);
        hook.setTickLowerDelta(_tickLowerDelta);
        _setComponents(address(hook));

        _setTokens(address(lendingAdapter));
        _setComponents(address(lendingAdapter));

        _setTokens(address(positionManager));
        _setComponents(address(positionManager));

        _setTokens(address(swapAdapter));
        _setComponents(address(swapAdapter));
        IUniswapV3SwapAdapter(address(swapAdapter)).setTargetPool(TARGET_SWAP_POOL);

        _setTokens(address(rebalanceAdapter));
        _setComponents(address(rebalanceAdapter));
        rebalanceAdapter.setSqrtPriceAtLastRebalance(initialSQRTPrice);
        rebalanceAdapter.setOraclePriceAtLastRebalance(oracle.price());
        rebalanceAdapter.setTimeAtLastRebalance(0);
        rebalanceAdapter.setIsUnicord(isUnicord);
        rebalanceAdapter.setRebalanceOperator(deployer.addr);
        // MARK END

        (address _token0, address _token1) = getTokensInOrder();
        (key, ) = initPool(Currency.wrap(_token0), Currency.wrap(_token1), hook, poolFee, initialSQRTPrice);

        // This is needed in order to simulate proper accounting
        deal(address(BASE), address(manager), 1000 ether);
        deal(address(QUOTE), address(manager), 1000 ether);
        vm.stopPrank();
    }

    function getTokensInOrder() internal view returns (address, address) {
        return !invertedPool ? (address(QUOTE), address(BASE)) : (address(BASE), address(QUOTE));
    }

    function _setTokens(address module) internal {
        IBase(module).setTokens(address(BASE), address(QUOTE), bDec, qDec);
    }

    function _setComponents(address module) internal {
        IBase(module).setComponents(
            address(hook),
            address(lendingAdapter),
            address(positionManager),
            address(oracle),
            address(rebalanceAdapter),
            address(swapAdapter)
        );
    }

    function approve_accounts() public virtual {
        vm.startPrank(alice.addr);
        BASE.forceApprove(address(hook), type(uint256).max);
        QUOTE.forceApprove(address(hook), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        BASE.forceApprove(address(swapRouter), type(uint256).max);
        QUOTE.forceApprove(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(marketMaker.addr);
        BASE.forceApprove(address(UNISWAP_V3_ROUTER), type(uint256).max);
        QUOTE.forceApprove(address(UNISWAP_V3_ROUTER), type(uint256).max);
        vm.stopPrank();
    }

    function alignOraclesAndPools(uint160 newSqrtPrice) public {
        vm.mockCall(
            address(hook.oracle()),
            abi.encodeWithSelector(IOracle.price.selector),
            abi.encode(_sqrtPriceToOraclePrice(newSqrtPrice))
        );
        setV3PoolPrice(newSqrtPrice);
    }

    // --- Uniswap V3 --- //

    function getHookPrice() public view returns (uint256) {
        return _sqrtPriceToOraclePrice(hook.sqrtPriceCurrent());
    }

    function getV3PoolPrice(address pool) public view returns (uint256) {
        return _sqrtPriceToOraclePrice(getV3PoolSQRTPrice(pool));
    }

    function getV3PoolSQRTPrice(address pool) public view returns (uint160) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        return sqrtPriceX96;
    }

    function getV3PoolTick(address pool) public view returns (int24) {
        (, int24 tick, , , , , ) = IUniswapV3Pool(pool).slot0();
        return tick;
    }

    function _sqrtPriceToOraclePrice(uint160 sqrtPriceX96) internal view returns (uint256) {
        return
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromSqrtPriceX96(sqrtPriceX96),
                invertedPool,
                uint8(ALMMathLib.absSub(bDec, qDec))
            );
    }

    uint256 minStepSize = 10 ether; // Minimum swap amount to prevent tiny swaps
    uint256 slippageTolerance = 1e18; // 1% acceptable price difference

    function setV3PoolPrice(uint160 newSqrtPrice) public {
        uint256 targetPrice = _sqrtPriceToOraclePrice(newSqrtPrice);

        // ** Configuration parameters
        uint256 initialStepSize = 1000 ether; // Initial swap amount
        uint256 adaptiveDecayBase = 90; // 90% decay when moving in right direction
        uint256 aggressiveDecayBase = 70; // 70% decay when overshooting

        uint256 currentPrice = getV3PoolPrice(TARGET_SWAP_POOL);
        uint256 previousPrice = currentPrice;
        uint256 stepSize = initialStepSize;

        uint256 iterations = 0;
        while (iterations < 50) {
            uint256 priceDiff = ALMMathLib.absSub(currentPrice, targetPrice);
            if (priceDiff <= slippageTolerance) break;
            iterations++;

            bool isZeroForOne = currentPrice >= targetPrice;
            if (invertedPool) isZeroForOne = !isZeroForOne;
            uint256 swapAmount = stepSize;
            if ((isZeroForOne && invertedPool) || (!isZeroForOne && !invertedPool))
                swapAmount = (stepSize * currentPrice) / 1e30;

            _doV3InputSwap(isZeroForOne, swapAmount);

            // Get new price and calculate improvement
            previousPrice = currentPrice;
            currentPrice = getV3PoolPrice(TARGET_SWAP_POOL);
            uint256 newPriceDiff = ALMMathLib.absSub(currentPrice, targetPrice);

            // Adaptive step size adjustment
            if (newPriceDiff < priceDiff) {
                stepSize = (stepSize * adaptiveDecayBase) / 100; // Moving in right direction
            } else {
                stepSize = (stepSize * aggressiveDecayBase) / 100; // Overshot or wrong direction
            }

            // Ensure minimum step size
            if (stepSize < minStepSize) stepSize = minStepSize;
        }

        console.log("Final price adjustment results:");
        console.log("Target price:", targetPrice);
        console.log("Final price:", currentPrice);
        console.log("Iterations:", iterations);

        if (ALMMathLib.absSub(currentPrice, targetPrice) > slippageTolerance) revert("setV3PoolPrice fail");
    }

    function _doV3InputSwap(bool zeroForOne, uint256 amountIn) internal returns (uint256 amountOut) {
        (address _token0, address _token1) = getTokensInOrder();
        deal(zeroForOne ? _token0 : _token1, address(marketMaker.addr), amountIn);
        vm.startPrank(marketMaker.addr);
        amountOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: zeroForOne ? _token0 : _token1,
                tokenOut: zeroForOne ? _token1 : _token0,
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

    function getFeeFromV3Pool(address pool) public view returns (uint24) {
        return IUniswapV3Pool(pool).fee();
    }

    // --- Uniswap V4 --- //

    function _swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (uint256, uint256) {
        (int256 delta0, int256 delta1) = __swap(zeroForOne, amount, _key);
        return (ALMMathLib.abs(delta0), ALMMathLib.abs(delta1));
    }

    function __swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (int256, int256) {
        (address _token0, address _token1) = getTokensInOrder();
        uint256 token0Before = IERC20(_token0).balanceOf(swapper.addr);
        uint256 token1Before = IERC20(_token1).balanceOf(swapper.addr);

        vm.startPrank(swapper.addr);
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
        vm.stopPrank();
        if (zeroForOne) {
            assertEq(token0Before - IERC20(_token0).balanceOf(swapper.addr), ALMMathLib.abs(delta.amount0()));
            assertEq(IERC20(_token1).balanceOf(swapper.addr) - token1Before, ALMMathLib.abs(delta.amount1()));
        } else {
            assertEq(IERC20(_token0).balanceOf(swapper.addr) - token0Before, ALMMathLib.abs(delta.amount0()));
            assertEq(token1Before - IERC20(_token1).balanceOf(swapper.addr), ALMMathLib.abs(delta.amount1()));
        }
        return (int256(delta.amount0()), int256(delta.amount1()));
    }

    // --- Custom assertions --- //

    uint256 public assertEqPSThresholdCL;
    uint256 public assertEqPSThresholdCS;
    uint256 public assertEqPSThresholdDL;
    uint256 public assertEqPSThresholdDS;
    uint256 public assertEqBalanceQuoteThreshold = 1e5;
    uint256 public assertEqBalanceBaseThreshold = 1e1;

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0);
    }

    function assertEqBalanceState(address owner, uint256 _balanceQ, uint256 _balanceB) public view {
        try this._assertEqBalanceState(owner, _balanceQ, _balanceB) {} catch {
            console.log("QUOTE Balance", QUOTE.balanceOf(owner));
            console.log("BASE Balance", BASE.balanceOf(owner));
            _assertEqBalanceState(owner, _balanceQ, _balanceB); // @Notice: this is to throw the error
        }
    }

    function _assertEqBalanceState(address owner, uint256 _balanceQ, uint256 _balanceB) public view {
        assertApproxEqAbs(
            QUOTE.balanceOf(owner),
            _balanceQ,
            assertEqBalanceQuoteThreshold,
            string.concat("Balance ", quoteName, " not equal")
        );
        assertApproxEqAbs(
            BASE.balanceOf(owner),
            _balanceB,
            assertEqBalanceBaseThreshold,
            string.concat("Balance ", baseName, " not equal")
        );
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

        uint256 diffDS = calcDS > _lendingAdapter.getBorrowedShort()
            ? calcDS - _lendingAdapter.getBorrowedShort()
            : _lendingAdapter.getBorrowedShort() - calcDS;

        assertApproxEqAbs(calcCL, _lendingAdapter.getCollateralLong(), 1e1);
        assertApproxEqAbs(calcCS, c18to6(_lendingAdapter.getCollateralShort()), 1e1);
        assertApproxEqAbs(calcDL, c18to6(_lendingAdapter.getBorrowedLong()), slippage);

        assertApproxEqAbs((diffDS * 1e18) / calcDS, slippage, slippage);

        uint256 tvlRatio = hook.TVL() > preRebalanceTVL
            ? (hook.TVL() * 1e18) / preRebalanceTVL - 1e18
            : 1e18 - (hook.TVL() * 1e18) / preRebalanceTVL;

        assertApproxEqAbs(tvlRatio, slippage, slippage);
    }

    function assertEqHookPositionStateDN(
        uint256 preRebalanceTVL,
        uint256 weight,
        uint256 longLeverage,
        uint256 shortLeverage,
        uint256 slippage
    ) public view {
        ILendingAdapter _lendingAdapter = ILendingAdapter(hook.lendingAdapter());

        uint256 calcCL = (preRebalanceTVL * (weight * longLeverage)) / oracle.price() / 1e18;

        uint256 calcCS = ((preRebalanceTVL * (1e18 - weight) * shortLeverage) / 1e48);

        uint256 calcDL = (((calcCL * oracle.price() * (1e18 - (1e36 / longLeverage))) / 1e36) * (1e18 + slippage)) /
            1e30;
        uint256 calcDS = (((calcCS * (1e18 - (1e36 / shortLeverage)) * 1e18) / oracle.price()) * (1e18 + slippage)) /
            1e24;

        uint256 diffDS = calcDS > _lendingAdapter.getBorrowedShort()
            ? calcDS - _lendingAdapter.getBorrowedShort()
            : _lendingAdapter.getBorrowedShort() - calcDS;

        assertApproxEqAbs(calcCL, _lendingAdapter.getCollateralLong(), 1e1);
        assertApproxEqAbs(calcCS, c18to6(_lendingAdapter.getCollateralShort()), 1e1);
        assertApproxEqAbs(calcDL, c18to6(_lendingAdapter.getBorrowedLong()), slippage);

        assertApproxEqAbs((diffDS * 1e18) / calcDS, slippage, slippage);

        uint256 tvlRatio = hook.TVL() > preRebalanceTVL
            ? (hook.TVL() * 1e18) / preRebalanceTVL - 1e18
            : 1e18 - (hook.TVL() * 1e18) / preRebalanceTVL;

        assertApproxEqAbs(tvlRatio, slippage, slippage);
    }

    function assertEqPositionState(uint256 CL, uint256 CS, uint256 DL, uint256 DS) public view {
        ILendingAdapter _leA = ILendingAdapter(hook.lendingAdapter()); // @Notice: The LA can change in tests
        try this._assertEqPositionState(CL, CS, DL, DS) {} catch {
            console.log("CL", TW.unwrap(_leA.getCollateralLong(), qDec));
            console.log("CS", TW.unwrap(_leA.getCollateralShort(), bDec));
            console.log("DL", TW.unwrap(_leA.getBorrowedLong(), bDec));
            console.log("DS", TW.unwrap(_leA.getBorrowedShort(), qDec));
            _assertEqPositionState(CL, CS, DL, DS); // @Notice: this is to throw the error
        }
    }

    function _assertEqPositionState(uint256 CL, uint256 CS, uint256 DL, uint256 DS) public view {
        ILendingAdapter _leA = ILendingAdapter(hook.lendingAdapter()); // @Notice: The LA can change in tests
        assertApproxEqAbs(TW.unwrap(_leA.getCollateralLong(), qDec), CL, assertEqPSThresholdCL, "CL not equal");
        assertApproxEqAbs(TW.unwrap(_leA.getCollateralShort(), bDec), CS, assertEqPSThresholdCS, "CS not equal");
        assertApproxEqAbs(TW.unwrap(_leA.getBorrowedLong(), bDec), DL, assertEqPSThresholdDL, "DL not equal");
        assertApproxEqAbs(TW.unwrap(_leA.getBorrowedShort(), qDec), DS, assertEqPSThresholdDS, "DS not equal");
    }

    // --- Test math --- //

    function _checkSwap(
        uint256 liquidity,
        uint160 preSqrtPrice,
        uint160 postSqrtPrice
    ) public view returns (uint256, uint256) {
        uint256 deltaX;
        uint256 deltaY;
        {
            uint256 prePrice = 1e48 / ALMMathLib.getPriceFromSqrtPriceX96(preSqrtPrice);
            uint256 postPrice = 1e48 / ALMMathLib.getPriceFromSqrtPriceX96(postSqrtPrice);

            //uint256 priceLower = 1e48 / ALMMathLib.getPriceFromTick(hook.tickLower()); //stack too deep
            uint256 priceUpper = 1e48 / ALMMathLib.getPriceFromTick(hook.tickUpper());

            uint256 preX = (liquidity * 1e18 * (priceUpper.sqrt() - prePrice.sqrt())) /
                ((priceUpper * prePrice) / 1e18).sqrt();
            uint256 postX = (liquidity * 1e27 * (priceUpper.sqrt() - postPrice.sqrt())) /
                (priceUpper * postPrice).sqrt();

            uint256 preY = (liquidity *
                (prePrice.sqrt() - (1e48 / ALMMathLib.getPriceFromTick(hook.tickLower())).sqrt())) / 1e12;
            uint256 postY = (liquidity *
                (postPrice.sqrt() - (1e48 / ALMMathLib.getPriceFromTick(hook.tickLower())).sqrt())) / 1e12;

            deltaX = postX > preX ? postX - preX : preX - postX;
            deltaY = postY > preY ? postY - preY : preY - postY;
        }

        return (deltaX, deltaY);
    }

    function _checkSwapReverse(
        uint256 liquidity,
        uint160 preSqrtPrice,
        uint160 postSqrtPrice
    ) public view returns (uint256, uint256) {
        uint256 deltaX;
        uint256 deltaY;
        {
            uint256 prePrice = 1e12 * ALMMathLib.getPriceFromSqrtPriceX96(preSqrtPrice);
            uint256 postPrice = 1e12 * ALMMathLib.getPriceFromSqrtPriceX96(postSqrtPrice);

            //uint256 priceLower = 1e48 / ALMMathLib.getPriceFromTick(hook.tickLower()); //stack too deep
            uint256 priceUpper = 1e12 * ALMMathLib.getPriceFromTick(hook.tickUpper());

            uint256 preX = (liquidity * 1e18 * (priceUpper.sqrt() - prePrice.sqrt())) /
                ((priceUpper * prePrice) / 1e18).sqrt();
            uint256 postX = (liquidity * 1e27 * (priceUpper.sqrt() - postPrice.sqrt())) /
                (priceUpper * postPrice).sqrt();

            uint256 preY = (liquidity *
                (prePrice.sqrt() - (1e12 * ALMMathLib.getPriceFromTick(hook.tickLower())).sqrt())) / 1e12;
            uint256 postY = (liquidity *
                (postPrice.sqrt() - (1e12 * ALMMathLib.getPriceFromTick(hook.tickLower())).sqrt())) / 1e12;

            deltaX = postX > preX ? postX - preX : preX - postX;
            deltaY = postY > preY ? postY - preY : preY - postY;
        }

        return (deltaX, deltaY);
    }

    function _checkSwapUnicord(
        uint256 liquidity,
        uint160 preSqrtPrice,
        uint160 postSqrtPrice
    ) public view returns (uint256, uint256) {
        uint256 deltaX;
        uint256 deltaY;
        {
            uint256 prePrice = ALMMathLib.getPriceFromSqrtPriceX96(preSqrtPrice);
            uint256 postPrice = ALMMathLib.getPriceFromSqrtPriceX96(postSqrtPrice);

            uint256 priceUpper = 1e36 / ALMMathLib.getPriceFromTick(hook.tickUpper());

            uint256 preX = (liquidity * 1e18 * (priceUpper.sqrt() - prePrice.sqrt())) /
                (((priceUpper * prePrice) / 1e18).sqrt());

            uint256 postX = (liquidity * 1e27 * (priceUpper.sqrt() - postPrice.sqrt())) /
                ((priceUpper * postPrice).sqrt());

            uint256 preY = (liquidity *
                (prePrice.sqrt() - (1e48 / ALMMathLib.getPriceFromTick(hook.tickLower())).sqrt())) / 1e12;
            uint256 postY = (liquidity *
                (postPrice.sqrt() - (1e48 / ALMMathLib.getPriceFromTick(hook.tickLower())).sqrt())) / 1e12;

            deltaX = postX > preX ? postX - preX : preX - postX;
            deltaY = postY > preY ? postY - preY : preY - postY;
        }

        return (deltaX, deltaY);
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
