// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** V4 imports
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Deployers} from "v4-core-test/utils/Deployers.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {EulerFlashLoanAdapter} from "@src/core/flashLoanAdapters/EulerFlashLoanAdapter.sol";
import {PositionManager} from "@src/core/positionManagers/PositionManager.sol";
import {UnicordPositionManager} from "@src/core/positionManagers/UnicordPositionManager.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";
import {Oracle} from "@src/core/oracles/Oracle.sol";
import {V4Quoter} from "v4-periphery/src/lens/V4Quoter.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
import {LiquidityAmounts} from "@src/libraries/LiquidityAmounts.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {IFlashLoanAdapter} from "@src/interfaces/IFlashLoanAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {ISwapAdapter} from "@src/interfaces/swapAdapters/ISwapAdapter.sol";
import {IUniswapSwapAdapter} from "@src/interfaces/swapAdapters/IUniswapSwapAdapter.sol";
import {ISwapRouter} from "@uniswap-v3/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap-v3/IUniswapV3Pool.sol";
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

abstract contract ALMTestBase is Deployers {
    using TestAccountLib for TestAccount;
    using CurrencyLibrary for Currency;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;

    V4Quoter quoter;
    uint160 initialSQRTPrice;
    ALM hook;
    SRebalanceAdapter rebalanceAdapter;

    address public TARGET_SWAP_POOL = TestLib.uniswap_v3_WETH_USDC_POOL;

    IERC20 BASE;
    IERC20 QUOTE;

    string baseName;
    string quoteName;

    uint8 bDec;
    uint8 qDec;

    bool isInvertedPool = true;

    ILendingAdapter lendingAdapter;
    IFlashLoanAdapter flashLoanAdapter;
    IPositionManager positionManager;
    ISwapAdapter swapAdapter;
    IOracle oracle;

    TestAccount deployer;
    TestAccount alice;
    TestAccount migrationContract;
    TestAccount swapper;
    TestAccount marketMaker;
    TestAccount zero;
    TestAccount treasury;

    uint256 almId;
    uint256 tempGas;

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
        treasury = TestAccountLib.createTestAccount("treasury");
    }

    function create_lending_adapter_euler_WETH_USDC() internal {
        create_lending_adapter_euler(TestLib.eulerUSDCVault1, 0, TestLib.eulerWETHVault1, 0);
    }

    function create_flash_loan_adapter_euler_WETH_USDC() internal {
        create_flash_loan_adapter_euler(TestLib.eulerUSDCVault2, 0, TestLib.eulerWETHVault2, 0);
    }

    function create_lending_adapter_euler(
        IEulerVault _vault0,
        uint256 deposit0,
        IEulerVault _vault1,
        uint256 deposit1
    ) internal {
        vm.prank(deployer.addr);
        lendingAdapter = new EulerLendingAdapter(
            BASE,
            QUOTE,
            TestLib.EULER_VAULT_CONNECT,
            _vault0,
            _vault1,
            TestLib.merklRewardsDistributor,
            TestLib.rEUL
        );
        _deposit_to_euler(_vault0, deposit0);
        _deposit_to_euler(_vault1, deposit1);
    }

    function create_flash_loan_adapter_euler(
        IEulerVault _flVault0,
        uint256 deposit0,
        IEulerVault _flVault1,
        uint256 deposit1
    ) internal {
        vm.prank(deployer.addr);
        flashLoanAdapter = new EulerFlashLoanAdapter(BASE, QUOTE, _flVault0, _flVault1);
        _deposit_to_euler(_flVault0, deposit0);
        _deposit_to_euler(_flVault1, deposit1);
    }

    function _deposit_to_euler(IEulerVault vault, uint256 toSupply) internal {
        if (toSupply == 0) return;
        address asset = vault.asset();
        deal(asset, address(marketMaker.addr), toSupply);

        vm.startPrank(marketMaker.addr);
        IERC20(asset).forceApprove(address(vault), type(uint256).max);
        vault.mint(vault.convertToShares(toSupply), marketMaker.addr);
        vm.stopPrank();
    }

    function create_oracle(
        bool _isInvertedPool,
        AggregatorV3Interface feedQ,
        AggregatorV3Interface feedB,
        uint256 stalenessThresholdQ,
        uint256 stalenessThresholdB
    ) internal returns (IOracle _oracle) {
        isInvertedPool = _isInvertedPool;
        vm.prank(deployer.addr);
        _oracle = new Oracle(
            feedB,
            feedQ,
            stalenessThresholdB,
            stalenessThresholdQ,
            _isInvertedPool,
            int8(bDec) - int8(qDec)
        );
        oracle = _oracle;
    }

    function _create_oracle(
        AggregatorV3Interface feedQ,
        AggregatorV3Interface feedB,
        uint256 stalenessThresholdQ,
        uint256 stalenessThresholdB,
        bool _isInvertedPool,
        int8 decimalsDelta
    ) internal returns (IOracle _oracle) {
        isInvertedPool = _isInvertedPool;
        vm.prank(deployer.addr);
        _oracle = new Oracle(feedB, feedQ, stalenessThresholdB, stalenessThresholdQ, _isInvertedPool, decimalsDelta);
        oracle = _oracle;
    }

    function init_hook(
        bool _isInvertedAssets,
        bool _isNova,
        uint256 _liquidityMultiplier,
        uint256 _protocolFee,
        uint256 _tvlCap,
        int24 _tickLowerDelta,
        int24 _tickUpperDelta,
        uint256 _swapPriceThreshold
    ) internal {
        console.log("v3Pool: initialPrice %s", getV3PoolPrice(TARGET_SWAP_POOL));
        console.log("v3Pool: initialSQRTPrice %s", initialSQRTPrice);
        console.log("v3Pool: initialTick %s", getV3PoolTick(TARGET_SWAP_POOL));
        console.log("oracle: initialPrice %s", oraclePriceW());
        vm.startPrank(deployer.addr);

        deploy_hook_contract(_isInvertedAssets);

        // MARK: Deploying modules and setting up parameters
        // LendingAdapter should already be created
        if (_isNova) positionManager = new UnicordPositionManager(BASE, QUOTE);
        else positionManager = new PositionManager(BASE, QUOTE);

        swapAdapter = new UniswapSwapAdapter(BASE, QUOTE, TestLib.UNIVERSAL_ROUTER, TestLib.PERMIT_2);
        // Oracle should already be created
        rebalanceAdapter = new SRebalanceAdapter(BASE, QUOTE, isInvertedPool, _isInvertedAssets, _isNova);

        hook.setProtocolParams(
            _liquidityMultiplier,
            _protocolFee,
            _tvlCap,
            _tickLowerDelta,
            _tickUpperDelta,
            _swapPriceThreshold
        );
        _setComponents(address(hook));

        _setComponents(address(lendingAdapter));
        _setComponents(address(flashLoanAdapter));
        _setComponents(address(positionManager));

        _setComponents(address(swapAdapter));
        setSwapAdapterToV3SingleSwap();

        _setComponents(address(rebalanceAdapter));
        rebalanceAdapter.setRebalanceOperator(deployer.addr);
        rebalanceAdapter.setLastRebalanceSnapshot(oracle.price(), initialSQRTPrice, 0);
        // MARK END

        initPool(key.currency0, key.currency1, key.hooks, key.fee, key.tickSpacing, initialSQRTPrice);

        // This is needed in order to simulate proper accounting
        deal(address(BASE), address(manager), 1000 ether);
        deal(address(QUOTE), address(manager), 1000 ether);

        quoter = new V4Quoter(manager);
        vm.stopPrank();
    }

    function deploy_hook_contract(bool _isInvertedAssets) internal {
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.AFTER_SWAP_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );

        (address currency0, address currency1) = getTokensInOrder();
        key = PoolKey(
            Currency.wrap(currency0),
            Currency.wrap(currency1),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            1, // The value of tickSpacing doesn't matter because it will change to the dynamic fee on afterInitialize
            IHooks(hookAddress)
        );
        deployCodeTo(
            "ALM.sol",
            abi.encode(key, BASE, QUOTE, isInvertedPool, _isInvertedAssets, manager, "NAME", "SYMBOL"),
            hookAddress
        );
        hook = ALM(hookAddress);
        vm.label(address(hook), "hook");
        assertEq(hook.owner(), deployer.addr);
    }

    function updateProtocolFees(uint256 _protocolFee) internal {
        (int24 lower, int24 upper) = hook.tickDeltas();
        hook.setProtocolParams(
            hook.liquidityMultiplier(),
            _protocolFee,
            hook.tvlCap(),
            lower,
            upper,
            hook.swapPriceThreshold()
        );
    }

    function updateProtocolTVLCap(uint256 _tvlCap) internal {
        (int24 lower, int24 upper) = hook.tickDeltas();
        hook.setProtocolParams(
            hook.liquidityMultiplier(),
            hook.protocolFee(),
            _tvlCap,
            lower,
            upper,
            hook.swapPriceThreshold()
        );
    }

    function updateProtocolPriceThreshold(uint256 _swapPriceThreshold) internal {
        (int24 lower, int24 upper) = hook.tickDeltas();
        hook.setProtocolParams(
            hook.liquidityMultiplier(),
            hook.protocolFee(),
            hook.tvlCap(),
            lower,
            upper,
            _swapPriceThreshold
        );
    }

    function setSwapAdapterToV3SingleSwap() internal {
        IUniswapSwapAdapter(address(swapAdapter)).setRoutesOperator(deployer.addr);

        uint256 fee = IUniswapV3Pool(TARGET_SWAP_POOL).fee();

        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(0, 1, abi.encodePacked(BASE, uint24(fee), QUOTE));
        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(1, 1, abi.encodePacked(QUOTE, uint24(fee), BASE));

        uint256[] memory activeSwapRoute = new uint256[](1);
        activeSwapRoute[0] = 0;
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, true, activeSwapRoute);
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, false, activeSwapRoute);

        activeSwapRoute[0] = 1;
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, true, activeSwapRoute);
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, false, activeSwapRoute);
    }

    function getTokensInOrder() internal view returns (address, address) {
        return !isInvertedPool ? (address(QUOTE), address(BASE)) : (address(BASE), address(QUOTE));
    }

    function _setComponents(address module) internal {
        IBase(module).setComponents(
            hook,
            lendingAdapter,
            flashLoanAdapter,
            positionManager,
            oracle,
            rebalanceAdapter,
            swapAdapter
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
        BASE.forceApprove(address(TestLib.UNISWAP_V3_ROUTER), type(uint256).max);
        QUOTE.forceApprove(address(TestLib.UNISWAP_V3_ROUTER), type(uint256).max);
        vm.stopPrank();
    }

    uint256 constant WAD = 1e18;
    function alignOraclesAndPools(uint160 newSqrtPrice) public {
        uint256 _poolPrice = TestLib.getPriceFromSqrtPriceX96(newSqrtPrice);

        uint256 _oraclePrice = TestLib.getOraclePriceFromPoolPrice(_poolPrice, isInvertedPool, int8(bDec) - int8(qDec));
        uint256 ratio = 10 ** uint256(int256(int8(bDec) - int8(qDec)) + 18);
        uint256 _price = _oraclePrice.mul(ratio);

        vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(_price));
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IOracle.poolPrice.selector),
            abi.encode(_price, _poolPrice)
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
            TestLib.getOraclePriceFromPoolPrice(
                TestLib.getPriceFromSqrtPriceX96(sqrtPriceX96),
                isInvertedPool,
                int8(bDec) - int8(qDec)
            );
    }

    uint256 minStepSize = 10 ether; // Minimum swap amount to prevent tiny swaps
    uint256 slippageTolerance = 1e16; // 1% acceptable price difference

    function _setV3PoolPrice(uint160 newSqrtPrice) public {
        uint256 targetPrice = _sqrtPriceToOraclePrice(newSqrtPrice);

        // ** Configuration parameters
        uint256 initialStepSize = 1000 ether; // Initial swap amount
        uint256 adaptiveDecayBase = 90; // 90% decay when moving in right direction
        uint256 aggressiveDecayBase = 70; // 70% decay when overshooting

        uint256 currentPrice = getV3PoolPrice(TARGET_SWAP_POOL);
        uint256 previousPrice = currentPrice;
        uint256 stepSize = initialStepSize;

        uint256 iterations = 0;
        while (iterations < 100) {
            uint256 priceDiff = ALMMathLib.absSub(currentPrice, targetPrice);
            if (priceDiff <= slippageTolerance) break;
            iterations++;

            bool isZeroForOne = currentPrice >= targetPrice;
            if (isInvertedPool) isZeroForOne = !isZeroForOne;
            uint256 swapAmount = stepSize;
            if ((isZeroForOne && isInvertedPool) || (!isZeroForOne && !isInvertedPool))
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

        // console.log("Final price adjustment results:");
        // console.log("Target price:", targetPrice);
        // console.log("Final price:", currentPrice);
        // console.log("Iterations:", iterations);

        if (ALMMathLib.absSub(currentPrice, targetPrice) > slippageTolerance) revert("setV3PoolPrice fail");
    }

    uint256 constant MAX_ITER = 8; // binary-search depth
    uint256 constant MIN_IN = 3e8; // 300 USDC   (token1)  or 0.0000003 WETH (token0)

    function setV3PoolPrice(uint160 targetSqrtPriceX96) public {
        uint160 sqrtCurrent = hook.sqrtPriceCurrent();
        if (sqrtCurrent == targetSqrtPriceX96) return;

        // ── 0. quick exit if already in band ────────────────────────────────
        uint256 priceTarget = _sqrtPriceToOraclePrice(targetSqrtPriceX96); // 1e18 scale
        uint256 priceCurrent = _sqrtPriceToOraclePrice(sqrtCurrent);
        if (ALMMathLib.absSub(priceTarget, priceCurrent) <= slippageTolerance) return;

        // ── 1. direction + liquidity snapshot ──────────────────────────────
        bool zeroForOne = priceCurrent > priceTarget; // pool price must drop
        if (isInvertedPool) zeroForOne = !zeroForOne; // flip when quoting inverted
        uint128 L = hook.liquidity();

        // Use binary search on the delta-amount rather than on price itself:
        // upper = “enough to overshoot”, lower = 0.  Each step halves the gap.
        uint256 hi;
        uint256 lo = 0;

        // upper bound:  move **whole** way in one go (worst case)
        if (zeroForOne) {
            // token0 in
            hi = SqrtPriceMath.getAmount0Delta(targetSqrtPriceX96, sqrtCurrent, L, true);
        } else {
            // token1 in
            hi = SqrtPriceMath.getAmount1Delta(sqrtCurrent, targetSqrtPriceX96, L, true);
        }

        if (hi < MIN_IN) hi = MIN_IN;

        // ── 2. iterative refinement ( ≤ 8 swaps ) ──────────────────────────
        for (uint8 i; i < MAX_ITER; ++i) {
            uint256 mid = (hi + lo) >> 1; // round-down
            if (mid < MIN_IN) mid = MIN_IN;

            // do the trial swap
            _doV3InputSwap(zeroForOne, mid);

            // compute new price
            sqrtCurrent = hook.sqrtPriceCurrent();
            priceCurrent = _sqrtPriceToOraclePrice(sqrtCurrent);

            // good enough?
            uint256 diff = ALMMathLib.absSub(priceCurrent, priceTarget);
            if (diff <= slippageTolerance) return;

            bool nowAbove = priceCurrent > priceTarget;
            if (nowAbove == (isInvertedPool ? !zeroForOne : zeroForOne)) {
                // we are still on the start side – need more input
                lo = mid;
            } else {
                // we overshot – mid was too large
                hi = mid;
            }
        }

        revert("setV3PoolPrice: cannot converge");
    }

    function _doV3InputSwap(bool zeroForOne, uint256 amountIn) internal returns (uint256 amountOut) {
        (address _token0, address _token1) = getTokensInOrder();
        deal(zeroForOne ? _token0 : _token1, address(marketMaker.addr), amountIn);
        vm.startPrank(marketMaker.addr);
        amountOut = TestLib.UNISWAP_V3_ROUTER.exactInputSingle(
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

    function _quoteOutputSwap(bool zeroForOne, uint256 amount) internal returns (uint256, uint256) {
        return
            quoter.quoteExactOutputSingle(
                IV4Quoter.QuoteExactSingleParams({
                    poolKey: key,
                    zeroForOne: zeroForOne,
                    exactAmount: SafeCast.toUint128(amount),
                    hookData: ""
                })
            );
    }

    function _swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (uint256, uint256) {
        (int256 delta0, int256 delta1) = __swap(zeroForOne, amount, _key);
        return (abs(delta0), abs(delta1));
    }

    function __swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (int256, int256) {
        (address _token0, address _token1) = getTokensInOrder();
        uint256 token0Before = IERC20(_token0).balanceOf(swapper.addr);
        uint256 token1Before = IERC20(_token1).balanceOf(swapper.addr);

        vm.startPrank(swapper.addr);
        BalanceDelta delta = swapRouter.swap(
            _key,
            SwapParams(
                zeroForOne,
                amount,
                zeroForOne == true ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        vm.stopPrank();
        if (zeroForOne) {
            assertEq(token0Before - IERC20(_token0).balanceOf(swapper.addr), abs(delta.amount0()));
            assertEq(IERC20(_token1).balanceOf(swapper.addr) - token1Before, abs(delta.amount1()));
        } else {
            assertEq(IERC20(_token0).balanceOf(swapper.addr) - token0Before, abs(delta.amount0()));
            assertEq(token1Before - IERC20(_token1).balanceOf(swapper.addr), abs(delta.amount1()));
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
    uint256 public assertEqSqrtThreshold;

    mapping(address => uint256) public balanceB;
    mapping(address => uint256) public balanceQ;

    function saveBalance(address owner) public {
        balanceB[owner] = BASE.balanceOf(owner);
        balanceQ[owner] = QUOTE.balanceOf(owner);
    }

    function assertBalanceNotChanged(address owner, uint256 precision) public view {
        assertApproxEqAbs(BASE.balanceOf(owner), balanceB[owner], precision, "BASE balance");
        assertApproxEqAbs(QUOTE.balanceOf(owner), balanceQ[owner], precision, "QUOTE balance");
    }

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0);
    }

    function assertEqBalanceState(address owner, uint256 _balanceQ, uint256 _balanceB) public view {
        try this._assertEqBalanceState(owner, _balanceQ, _balanceB) {
            // Intentionally empty
        } catch {
            console.log("Error: QUOTE Balance", QUOTE.balanceOf(owner));
            console.log("Error: BASE Balance", BASE.balanceOf(owner));
            _assertEqBalanceState(owner, _balanceQ, _balanceB); // This is to throw the error
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

    function assertTicks(int24 lower, int24 upper) internal view {
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        assertEq(tickLower, lower);
        assertEq(tickUpper, upper);
    }

    function assertEqHookPositionState(
        uint256 preRebalanceTVL,
        uint256 weight,
        uint256 longLeverage,
        uint256 shortLeverage,
        uint256 slippage
    ) public view {
        ILendingAdapter _lendingAdapter = ILendingAdapter(hook.lendingAdapter());

        uint256 calcDS;

        uint256 calcCL = (preRebalanceTVL * (weight * longLeverage)) / 1e36;

        uint256 calcCS = (((preRebalanceTVL * oraclePriceW()) / 1e18) * (((1e18 - weight) * shortLeverage) / 1e18)) /
            1e30;

        uint256 calcDL = (((calcCL * oraclePriceW() * (1e18 - (1e36 / longLeverage))) / 1e36) * (1e18 + slippage)) /
            1e30;
        if (shortLeverage != 1e18)
            calcDS = (((calcCS * (1e18 - (1e36 / shortLeverage)) * 1e18) / oraclePriceW()) * (1e18 + slippage)) / 1e24;

        uint256 diffDS = calcDS >= _lendingAdapter.getBorrowedShort()
            ? calcDS - _lendingAdapter.getBorrowedShort()
            : _lendingAdapter.getBorrowedShort() - calcDS;

        uint256 diffDL = calcDL >= _lendingAdapter.getBorrowedLong()
            ? calcDL - _lendingAdapter.getBorrowedLong()
            : _lendingAdapter.getBorrowedLong() - calcDL;

        assertApproxEqAbs(calcCL, _lendingAdapter.getCollateralLong(), 100);
        assertApproxEqAbs(calcCS, _lendingAdapter.getCollateralShort(), 100);
        // assertApproxEqAbs(calcDL * 1e18 /_lendingAdapter.getBorrowedLong(), , slippage);
        assertApproxEqAbs((diffDL * 1e18) / calcDS, slippage, slippage);

        if (shortLeverage != 1e18) assertApproxEqAbs((diffDS * 1e18) / calcDS, slippage, slippage);

        uint256 tvlRatio = calcTVL() > preRebalanceTVL
            ? (calcTVL() * 1e18) / preRebalanceTVL - 1e18
            : 1e18 - (calcTVL() * 1e18) / preRebalanceTVL;

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

        uint256 calcCL = (preRebalanceTVL * (weight * longLeverage)) / oraclePriceW() / 1e18;

        uint256 calcCS = ((preRebalanceTVL * (1e18 - weight) * shortLeverage) / 1e48);

        uint256 calcDL = (((calcCL * oraclePriceW() * (1e18 - (1e36 / longLeverage))) / 1e36) * (1e18 + slippage)) /
            1e30;
        uint256 calcDS = (((calcCS * (1e18 - (1e36 / shortLeverage)) * 1e18) / oraclePriceW()) * (1e18 + slippage)) /
            1e24;

        uint256 diffDS = calcDS > _lendingAdapter.getBorrowedShort()
            ? calcDS - _lendingAdapter.getBorrowedShort()
            : _lendingAdapter.getBorrowedShort() - calcDS;

        assertApproxEqAbs(calcCL, _lendingAdapter.getCollateralLong(), 1e1);
        assertApproxEqAbs(calcCS, _lendingAdapter.getCollateralShort(), 1e1);
        assertApproxEqAbs(calcDL, _lendingAdapter.getBorrowedLong(), slippage);

        assertApproxEqAbs((diffDS * 1e18) / calcDS, slippage, slippage);

        uint256 tvlRatio = calcTVL() > preRebalanceTVL
            ? (calcTVL() * 1e18) / preRebalanceTVL - 1e18
            : 1e18 - (calcTVL() * 1e18) / preRebalanceTVL;

        assertApproxEqAbs(tvlRatio, slippage, slippage);
    }

    function assertEqPositionState(uint256 CL, uint256 CS, uint256 DL, uint256 DS) public view {
        ILendingAdapter _leA = ILendingAdapter(hook.lendingAdapter()); // The LA can change in tests
        try this._assertEqPositionState(CL, CS, DL, DS) {
            // Intentionally empty
        } catch {
            console.log("Error: CL", _leA.getCollateralLong());
            console.log("Error: CS", _leA.getCollateralShort());
            console.log("Error: DL", _leA.getBorrowedLong());
            console.log("Error: DS", _leA.getBorrowedShort());
            _assertEqPositionState(CL, CS, DL, DS); // This is to throw the error
        }
    }

    function _assertEqPositionState(uint256 CL, uint256 CS, uint256 DL, uint256 DS) public view {
        ILendingAdapter _leA = ILendingAdapter(hook.lendingAdapter()); // The LA can change in tests
        assertApproxEqAbs(_leA.getCollateralLong(), CL, assertEqPSThresholdCL, "CL not equal");
        assertApproxEqAbs(_leA.getCollateralShort(), CS, assertEqPSThresholdCS, "CS not equal");
        assertApproxEqAbs(_leA.getBorrowedLong(), DL, assertEqPSThresholdDL, "DL not equal");
        assertApproxEqAbs(_leA.getBorrowedShort(), DS, assertEqPSThresholdDS, "DS not equal");
    }

    function assertEqProtocolState(uint256 sqrtPriceCurrent, uint256 tvl) public view {
        try this._assertEqProtocolState(sqrtPriceCurrent, tvl) {
            // Intentionally empty
        } catch {
            console.log("Error: sqrtPriceCurrent", hook.sqrtPriceCurrent());
            console.log("Error: tvl", calcTVL());
            _assertEqProtocolState(sqrtPriceCurrent, tvl); // This is to throw the error
        }
    }

    function _assertEqProtocolState(uint256 sqrtPriceCurrent, uint256 tvl) public view {
        assertApproxEqAbs(hook.sqrtPriceCurrent(), sqrtPriceCurrent, 0, "sqrtPrice not equal");
        assertApproxEqAbs(calcTVL(), tvl, 0, "TVL not equal");
    }

    // --- Test math --- //

    function _checkSwap(
        uint128 liquidity,
        uint160 preSqrtPrice,
        uint160 postSqrtPrice
    ) public view returns (uint256, uint256) {
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        (uint256 amt0Pre, uint256 amt1Pre) = LiquidityAmounts.getAmountsForLiquidity(
            preSqrtPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );

        (uint256 amt0Post, uint256 amt1Post) = LiquidityAmounts.getAmountsForLiquidity(
            postSqrtPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );

        return (
            amt1Post > amt1Pre ? amt1Post - amt1Pre : amt1Pre - amt1Post,
            amt0Post > amt0Pre ? amt0Post - amt0Pre : amt0Pre - amt0Post
        );
    }

    function _liquidityCheck(bool _isInvertedPool, uint256 liquidityMultiplier) public view {
        uint128 liquidityCheck;
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        if (_isInvertedPool) {
            liquidityCheck = LiquidityAmounts.getLiquidityForAmount1(
                ALMMathLib.getSqrtPriceX96FromTick(tickLower),
                ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
                lendingAdapter.getCollateralLong()
            );
        } else {
            liquidityCheck = LiquidityAmounts.getLiquidityForAmount0(
                ALMMathLib.getSqrtPriceX96FromTick(tickLower),
                ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
                lendingAdapter.getCollateralLong()
            );
        }

        assertApproxEqAbs(hook.liquidity(), (liquidityCheck * liquidityMultiplier) / 1e18, 1, "liquidity");
    }

    function _checkSwapReverse(
        uint256 liquidity,
        uint160 preSqrtPrice,
        uint160 postSqrtPrice
    ) public view returns (uint256, uint256) {
        uint256 prePrice = 1e12 * TestLib.getPriceFromSqrtPriceX96(preSqrtPrice);
        uint256 postPrice = 1e12 * TestLib.getPriceFromSqrtPriceX96(postSqrtPrice);

        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        //uint256 priceLower = 1e48 / TestLib.getPriceFromTick(activeTicks.lower); //TODO: stack too deep?
        uint256 priceUpper = 1e12 * TestLib.getPriceFromTick(tickUpper);

        uint256 preX = (liquidity * 1e18 * (priceUpper.sqrt() - prePrice.sqrt())) /
            ((priceUpper * prePrice) / 1e18).sqrt();
        uint256 postX = (liquidity * 1e27 * (priceUpper.sqrt() - postPrice.sqrt())) / (priceUpper * postPrice).sqrt();

        uint256 preY = (liquidity * (prePrice.sqrt() - (1e12 * TestLib.getPriceFromTick(tickLower)).sqrt())) / 1e12;
        uint256 postY = (liquidity * (postPrice.sqrt() - (1e12 * TestLib.getPriceFromTick(tickLower)).sqrt())) / 1e12;

        return (postX > preX ? postX - preX : preX - postX, postY > preY ? postY - preY : preY - postY);
    }

    function _checkSwapUnicord(
        uint256 liquidity,
        uint160 preSqrtPrice,
        uint160 postSqrtPrice
    ) public view returns (uint256, uint256) {
        uint256 prePrice = TestLib.getPriceFromSqrtPriceX96(preSqrtPrice);
        uint256 postPrice = TestLib.getPriceFromSqrtPriceX96(postSqrtPrice);

        (int24 tickLower, int24 tickUpper) = hook.activeTicks();

        uint256 priceUpper = 1e36 / TestLib.getPriceFromTick(tickUpper);

        uint256 preX = (liquidity * 1e18 * (priceUpper.sqrt() - prePrice.sqrt())) /
            (((priceUpper * prePrice) / 1e18).sqrt());

        uint256 postX = (liquidity * 1e27 * (priceUpper.sqrt() - postPrice.sqrt())) / ((priceUpper * postPrice).sqrt());
        uint256 preY = (liquidity * (prePrice.sqrt() - (1e48 / TestLib.getPriceFromTick(tickLower)).sqrt())) / 1e12;
        uint256 postY = (liquidity * (postPrice.sqrt() - (1e48 / TestLib.getPriceFromTick(tickUpper)).sqrt())) / 1e12;
        return (postX > preX ? postX - preX : preX - postX, postY > preY ? postY - preY : preY - postY);
    }

    function calcTVL() internal view returns (uint256) {
        return hook.TVL(oracle.price());
    }

    function calcSharePrice(uint256 tS, uint256 TVL) internal pure returns (uint256) {
        if (tS == 0) return 0;
        return TVL.div(tS);
    }

    function recordGas() internal {
        tempGas = gasleft();
    }

    function logGas() internal {
        console.log("gasSpend", tempGas - gasleft());
        tempGas = 0;
    }

    // --- Utils --- //

    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }

    function _fakeSetComponents(address adapter, address fakeALM) internal {
        vm.mockCall(fakeALM, abi.encodeWithSelector(IALM.status.selector), abi.encode(0));
        vm.prank(deployer.addr);
        IBase(adapter).setComponents(
            IALM(fakeALM),
            ILendingAdapter(alice.addr),
            IFlashLoanAdapter(alice.addr),
            IPositionManager(alice.addr),
            IOracle(alice.addr),
            IRebalanceAdapter(alice.addr),
            ISwapAdapter(alice.addr)
        );
    }

    function otherToken(IERC20 token) internal view returns (IERC20) {
        if (token == BASE) return QUOTE;
        if (token == QUOTE) return BASE;
        revert("Token not allowed");
    }

    function poolPrice() internal view returns (uint256 _poolPrice) {
        (, _poolPrice) = oracle.poolPrice();
    }

    function oraclePriceW() internal view returns (uint256) {
        uint256 ratio = 10 ** uint256(int256(int8(bDec) - int8(qDec)) + 18);
        return oracle.price().div(ratio);
    }

    function oraclePrice() internal view returns (uint256) {
        return oracle.price();
    }
}
