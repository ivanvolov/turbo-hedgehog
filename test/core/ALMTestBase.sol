// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {MarketParamsLib} from "@forks/morpho/libraries/MarketParamsLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IChainlinkOracle} from "@forks/morpho-oracles/IChainlinkOracle.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id} from "@forks/morpho/IMorpho.sol";
import {ALM} from "@src/ALM.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {TestERC20} from "v4-core/test/TestERC20.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {MorphoLendingAdapter} from "@src/core/MorphoLendingAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

abstract contract ALMTestBase is Test, Deployers {
    using TestAccountLib for TestAccount;
    using CurrencyLibrary for Currency;

    uint160 initialSQRTPrice;
    ALM hook;
    uint24 constant poolFee = 100; // It's 2*100/100 = 2 ts. TODO: witch to set in production?
    SRebalanceAdapter rebalanceAdapter;

    TestERC20 USDC;
    TestERC20 WETH;

    ILendingAdapter lendingAdapter;

    TestAccount marketCreator;
    TestAccount morphoLpProvider;

    TestAccount deployer;
    TestAccount alice;
    TestAccount swapper;
    TestAccount zero;

    Id depositUSDCmId;
    Id borrowUSDCmId;
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    uint256 almId;

    function init_hook() internal {
        vm.startPrank(deployer.addr);

        // MARK: Usual UniV4 hook deployment process
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo("ALM.sol", abi.encode(manager), hookAddress);
        hook = ALM(hookAddress);
        vm.label(address(hook), "hook");
        assertEq(hook.hookDeployer(), deployer.addr);
        // MARK END

        rebalanceAdapter = new SRebalanceAdapter();
        lendingAdapter = new MorphoLendingAdapter();

        lendingAdapter.setDepositUSDCmId(depositUSDCmId);
        lendingAdapter.setBorrowUSDCmId(borrowUSDCmId);
        lendingAdapter.addAuthorizedCaller(address(hook));
        lendingAdapter.addAuthorizedCaller(address(rebalanceAdapter));

        rebalanceAdapter.setALM(address(hook));
        rebalanceAdapter.setLendingAdapter(address(lendingAdapter));
        rebalanceAdapter.setSqrtPriceLastRebalance(initialSQRTPrice);
        rebalanceAdapter.setTickDeltaThreshold(250);

        // MARK: Pool deployment
        PoolKey memory _key = PoolKey(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            poolFee,
            int24((poolFee / 100) * 2),
            hook
        ); // pre-compute key in order to restrict hook to this pool

        hook.setAuthorizedPool(_key);
        (key, ) = initPool(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            hook,
            poolFee,
            initialSQRTPrice,
            ""
        );

        hook.setLendingAdapter(address(lendingAdapter));
        hook.setRebalanceAdapter(address(rebalanceAdapter));
        assertEq(hook.tickLower(), 192230 + 3000);
        assertEq(hook.tickUpper(), 192230 - 3000);
        // MARK END

        // This is needed in order to simulate proper accounting
        deal(address(USDC), address(manager), 1000 ether);
        deal(address(WETH), address(manager), 1000 ether);
        vm.stopPrank();
    }

    function create_and_seed_morpho_markets() internal {
        address oracle = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

        modifyMockOracle(oracle, 4487851340816804029821232973); //4487 usdc for eth

        borrowUSDCmId = create_morpho_market(address(USDC), address(WETH), 915000000000000000, oracle);

        provideLiquidityToMorpho(borrowUSDCmId, 1000 ether); // Providing some ETH

        depositUSDCmId = create_morpho_market(address(USDC), address(WETH), 945000000000000000, oracle);
    }

    function presetChainlinkOracles() internal {
        vm.mockCall(
            address(ALMBaseLib.CHAINLINK_7_DAYS_VOL),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(18446744073709563265, 60444, 1725059436, 1725059436, 18446744073709563265)
        );

        vm.mockCall(
            address(ALMBaseLib.CHAINLINK_30_DAYS_VOL),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(18446744073709563266, 86480, 1725059412, 1725059412, 18446744073709563266)
        );
    }

    function create_accounts_and_tokens() public {
        WETH = TestERC20(ALMBaseLib.WETH);
        vm.label(address(WETH), "WETH");
        USDC = TestERC20(ALMBaseLib.USDC);
        vm.label(address(USDC), "USDC");

        marketCreator = TestAccountLib.createTestAccount("marketCreator");
        morphoLpProvider = TestAccountLib.createTestAccount("morphoLpProvider");
        deployer = TestAccountLib.createTestAccount("deployer");
        alice = TestAccountLib.createTestAccount("alice");
        swapper = TestAccountLib.createTestAccount("swapper");
        zero = TestAccountLib.createTestAccount("zero");
    }

    function approve_accounts() public {
        vm.startPrank(alice.addr);
        USDC.approve(address(hook), type(uint256).max);
        WETH.approve(address(hook), type(uint256).max);

        USDC.approve(address(morpho), type(uint256).max);
        WETH.approve(address(morpho), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        USDC.approve(address(swapRouter), type(uint256).max);
        WETH.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
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

    // -- Morpho -- //

    function create_morpho_market(
        address loanToken,
        address collateralToken,
        uint256 lltv,
        address oracle
    ) internal returns (Id) {
        MarketParams memory marketParams = MarketParams(
            loanToken,
            collateralToken,
            oracle,
            0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, // We have only 1 irm in morpho so we can use this address
            lltv
        );

        vm.prank(marketCreator.addr);
        morpho.createMarket(marketParams);
        return MarketParamsLib.id(marketParams);
    }

    function modifyMockOracle(address oracle, uint256 newPrice) internal returns (IChainlinkOracle iface) {
        //NOTICE: https://github.com/morpho-org/morpho-blue-oracles
        iface = IChainlinkOracle(oracle);

        vm.mockCall(address(oracle), abi.encodeWithSelector(iface.price.selector), abi.encode(newPrice));

        // console.log("> vault", address(iface.VAULT()));
        // console.log("> conversionSample", iface.VAULT_CONVERSION_SAMPLE());
        // console.log("> baseFeed1", address(iface.BASE_FEED_1()));
        // console.log("> baseFeed2", address(iface.BASE_FEED_2()));
        // console.log("> quoteFeed1", address(iface.QUOTE_FEED_1()));
        // console.log("> quoteFeed2", address(iface.QUOTE_FEED_2()));
        // console.log("> scaleFactor", iface.SCALE_FACTOR());
        return iface;
    }

    function provideLiquidityToMorpho(Id marketId, uint256 amount) internal {
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);

        vm.startPrank(morphoLpProvider.addr);
        deal(marketParams.loanToken, morphoLpProvider.addr, amount);

        TestERC20(marketParams.loanToken).approve(address(morpho), type(uint256).max);
        (, uint256 shares) = morpho.supply(marketParams, amount, 0, morphoLpProvider.addr, "");

        assertEqMorphoS(marketId, morphoLpProvider.addr, shares, 0, 0);
        assertEqBalanceStateZero(morphoLpProvider.addr);
        vm.stopPrank();
    }

    // -- Custom assertions -- //

    function assertEqMorphoS(
        Id marketId,
        uint256 _supplyShares,
        uint256 _borrowShares,
        uint256 _collateral
    ) public view {
        assertEqMorphoS(marketId, address(lendingAdapter), _supplyShares, _borrowShares, _collateral);
    }

    function assertEqMorphoS(
        Id marketId,
        address owner,
        uint256 _supplyShares,
        uint256 _borrowShares,
        uint256 _collateral
    ) public view {
        MorphoPosition memory p;
        p = morpho.position(marketId, owner);
        assertApproxEqAbs(p.supplyShares, _supplyShares, 10, "supply shares not equal");
        assertApproxEqAbs(p.borrowShares, _borrowShares, 10, "borrow shares not equal");
        assertApproxEqAbs(p.collateral, _collateral, 10000, "collateral not equal");
    }

    function assertEqMorphoA(
        Id marketId,
        uint256 _suppliedAssets,
        uint256 _borrowAssets,
        uint256 _collateral
    ) public view {
        assertEqMorphoA(marketId, address(lendingAdapter), _suppliedAssets, _borrowAssets, _collateral);
    }

    function assertEqMorphoA(
        Id marketId,
        address owner,
        uint256 _suppliedAssets,
        uint256 _borrowAssets,
        uint256 _collateral
    ) public view {
        MorphoPosition memory p;
        p = morpho.position(marketId, owner);

        assertApproxEqAbs(
            MorphoBalancesLib.expectedSupplyAssets(morpho, morpho.idToMarketParams(marketId), owner),
            _suppliedAssets,
            10,
            "supply assets not equal"
        );
        assertApproxEqAbs(
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(marketId), owner),
            _borrowAssets,
            10,
            "borrow assets not equal"
        );
        assertApproxEqAbs(p.collateral, _collateral, 10000, "collateral not equal");
    }

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
        assertApproxEqAbs(WETH.balanceOf(owner), _balanceWETH, 1000, "Balance WETH not equal");
        assertApproxEqAbs(USDC.balanceOf(owner), _balanceUSDC, 10, "Balance USDC not equal");
        assertApproxEqAbs(owner.balance, _balanceETH, 10, "Balance ETH not equal");
    }
}
