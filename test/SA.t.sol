// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapSwapAdapter} from "@src/interfaces/swapAdapters/IUniswapSwapAdapter.sol";
import {IUniswapV3Pool} from "@uniswap-v3/IUniswapV3Pool.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PathKey} from "v4-periphery/src/interfaces/IV4Router.sol";

contract SwapAdapterTest is ALMTestBase {
    using SafeERC20 for IERC20;
    using TokenWrapperLib for uint256;
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    IUniswapSwapAdapter uniswapSwapAdapter;

    PoolKey poolKeyETH_USDC;
    PoolKey poolKeyETH_USDT;
    PoolKey poolKeyUSDC_USDT;

    enum ProtocolType {
        V2,
        V3,
        V4_SINGLE,
        V4_MULTIHOP
    }

    enum SwapDirection {
        BASE_QUOTE,
        QUOTE_BASE
    }
    enum SwapType {
        EXACT_INPUT,
        EXACT_OUTPUT
    }

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(22490362);

        vm.label(address(ETH), "ETH");
        vm.label(TestLib.USDC, "USDC");
        vm.label(TestLib.USDT, "USDT");

        poolKeyETH_USDC = _getAndCheckPoolKey(
            ETH,
            IERC20(TestLib.USDC),
            500,
            10,
            0x21c67e77068de97969ba93d4aab21826d33ca12bb9f565d8496e8fda8a82ca27
        );

        poolKeyETH_USDT = _getAndCheckPoolKey(
            ETH,
            IERC20(TestLib.USDT),
            500,
            10,
            0x72331fcb696b0151904c03584b66dc8365bc63f8a144d89a773384e3a579ca73
        );

        poolKeyUSDC_USDT = _getAndCheckPoolKey(
            IERC20(TestLib.USDC),
            IERC20(TestLib.USDT),
            100,
            1,
            0xe018f09af38956affdfeab72c2cefbcd4e6fee44d09df7525ec9dba3e51356a5
        );
    }

    IERC20 ETH = IERC20(address(0));

    uint256 testAmount = 1000e6;

    function test_swapExactInput_V4_SINGLE_BASE_QUOTE() public {
        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.BASE_QUOTE,
            999621885,
            abi.encode(poolKeyUSDC_USDT, true, bytes("")),
            ProtocolType.V4_SINGLE
        );
    }

    function test_swapExactOutput_V4_SINGLE_BASE_QUOTE() public {
        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.BASE_QUOTE,
            1000378259,
            abi.encode(poolKeyUSDC_USDT, true, bytes("")),
            ProtocolType.V4_SINGLE
        );
    }

    function test_swapExactInput_V4_SINGLE_QUOTE_BASE() public {
        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.QUOTE_BASE,
            1000176859,
            abi.encode(poolKeyUSDC_USDT, false, bytes("")),
            ProtocolType.V4_SINGLE
        );
    }

    function test_swapExactOutput_V4_SINGLE_QUOTE_BASE() public {
        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.QUOTE_BASE,
            999823173,
            abi.encode(poolKeyUSDC_USDT, false, bytes("")),
            ProtocolType.V4_SINGLE
        );
    }

    function test_swapExactInput_V4_MULTIHOP_BASE_QUOTE() public {
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey(
            poolKeyETH_USDC.currency0,
            poolKeyETH_USDC.fee,
            poolKeyETH_USDC.tickSpacing,
            poolKeyETH_USDC.hooks,
            abi.encodePacked(uint8(1))
        ); // gives out ETH
        path[1] = PathKey(
            poolKeyETH_USDT.currency1,
            poolKeyETH_USDT.fee,
            poolKeyETH_USDT.tickSpacing,
            poolKeyETH_USDT.hooks,
            abi.encodePacked(uint8(2))
        ); // gives out USDT

        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.BASE_QUOTE,
            998357409,
            abi.encode(path),
            ProtocolType.V4_MULTIHOP
        );
    }

    function test_swapExactOutput_V4_MULTIHOP_BASE_QUOTE() public {
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey(
            poolKeyETH_USDC.currency1,
            poolKeyETH_USDC.fee,
            poolKeyETH_USDC.tickSpacing,
            poolKeyETH_USDC.hooks,
            abi.encodePacked(uint8(1))
        ); // gives out ETH
        path[1] = PathKey(
            poolKeyETH_USDT.currency0,
            poolKeyETH_USDT.fee,
            poolKeyETH_USDT.tickSpacing,
            poolKeyETH_USDT.hooks,
            abi.encodePacked(uint8(2))
        ); // gives out USDT
        // this gos backwards

        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.BASE_QUOTE,
            1001645736,
            abi.encode(path),
            ProtocolType.V4_MULTIHOP
        );
    }

    function test_swapExactInput_V4_MULTIHOP_QUOTE_BASE() public {
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey(
            poolKeyETH_USDT.currency0,
            poolKeyETH_USDT.fee,
            poolKeyETH_USDT.tickSpacing,
            poolKeyETH_USDT.hooks,
            bytes("")
        ); // gives out USDT
        path[1] = PathKey(
            poolKeyETH_USDC.currency1,
            poolKeyETH_USDC.fee,
            poolKeyETH_USDC.tickSpacing,
            poolKeyETH_USDC.hooks,
            bytes("")
        ); // gives out ETH

        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.QUOTE_BASE,
            999107408,
            abi.encode(path),
            ProtocolType.V4_MULTIHOP
        );
    }

    function test_swapExactOutput_V4_MULTIHOP_QUOTE_BASE() public {
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey(
            poolKeyETH_USDT.currency1,
            poolKeyETH_USDT.fee,
            poolKeyETH_USDT.tickSpacing,
            poolKeyETH_USDT.hooks,
            bytes("")
        ); // gives out USDT
        path[1] = PathKey(
            poolKeyETH_USDC.currency0,
            poolKeyETH_USDC.fee,
            poolKeyETH_USDC.tickSpacing,
            poolKeyETH_USDC.hooks,
            bytes("")
        ); // gives out ETH
        // this goes backwards

        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.QUOTE_BASE,
            1000893629,
            abi.encode(path),
            ProtocolType.V4_MULTIHOP
        );
    }

    function test_swapExactInput_V3_SINGLE_BASE_QUOTE() public {
        uint256 fee = IUniswapV3Pool(TestLib.uniswap_v3_USDC_USDT_POOL).fee();
        bytes memory path = abi.encodePacked(TestLib.USDC, uint24(fee), TestLib.USDT);

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.BASE_QUOTE, 999607371, path, ProtocolType.V3);
    }

    function test_swapExactOutput_V3_SINGLE_BASE_QUOTE() public {
        uint256 fee = IUniswapV3Pool(TestLib.uniswap_v3_USDC_USDT_POOL).fee();
        bytes memory path = abi.encodePacked(TestLib.USDT, uint24(fee), TestLib.USDC);

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.BASE_QUOTE, 1000392784, path, ProtocolType.V3);
    }

    function test_swapExactInput_V3_SINGLE_QUOTE_BASE() public {
        uint256 fee = IUniswapV3Pool(TestLib.uniswap_v3_USDC_USDT_POOL).fee();
        bytes memory path = abi.encodePacked(TestLib.USDT, uint24(fee), TestLib.USDC);

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.QUOTE_BASE, 1000192674, path, ProtocolType.V3);
    }

    function test_swapExactOutput_V3_SINGLE_QUOTE_BASE() public {
        uint256 fee = IUniswapV3Pool(TestLib.uniswap_v3_USDC_USDT_POOL).fee();
        bytes memory path = abi.encodePacked(TestLib.USDC, uint24(fee), TestLib.USDT);

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.QUOTE_BASE, 999807364, path, ProtocolType.V3);
    }

    function test_swapExactInput_V3_MULTIHOP_BASE_QUOTE() public {
        bytes memory path = abi.encodePacked(
            TestLib.USDC,
            uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDC_POOL).fee()),
            address(TestLib.WETH),
            uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDT_POOL).fee()),
            TestLib.USDT
        );

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.BASE_QUOTE, 996166709, path, ProtocolType.V3);
    }

    function test_swapExactOutput_V3_MULTIHOP_BASE_QUOTE() public {
        bytes memory path = abi.encodePacked(
            TestLib.USDT,
            uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDT_POOL).fee()),
            address(TestLib.WETH),
            uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDC_POOL).fee()),
            TestLib.USDC
        );

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.BASE_QUOTE, 1003848075, path, ProtocolType.V3);
    }

    function test_swapExactInput_V3_MULTIHOP_QUOTE_BASE() public {
        bytes memory path = abi.encodePacked(
            TestLib.USDT,
            uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDT_POOL).fee()),
            address(TestLib.WETH),
            uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDC_POOL).fee()),
            TestLib.USDC
        );

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.QUOTE_BASE, 996819823, path, ProtocolType.V3);
    }

    function test_swapExactOutput_V3_MULTIHOP_QUOTE_BASE() public {
        bytes memory path = abi.encodePacked(
            TestLib.USDC,
            uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDC_POOL).fee()),
            address(TestLib.WETH),
            uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDT_POOL).fee()),
            TestLib.USDT
        );

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.QUOTE_BASE, 1003190350, path, ProtocolType.V3);
    }

    function test_swapExactInput_V2_SINGLE_BASE_QUOTE() public {
        address[] memory path = new address[](2);
        path[0] = TestLib.USDC;
        path[1] = TestLib.USDT;
        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.BASE_QUOTE, 994454813, abi.encode(path), ProtocolType.V2);
    }

    function test_swapExactOutput_V2_SINGLE_BASE_QUOTE() public {
        address[] memory path = new address[](2);
        path[0] = TestLib.USDC;
        path[1] = TestLib.USDT;
        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.BASE_QUOTE, 1005579129, abi.encode(path), ProtocolType.V2);
    }

    function test_swapExactInput_V2_SINGLE_QUOTE_BASE() public {
        address[] memory path = new address[](2);
        path[0] = TestLib.USDT;
        path[1] = TestLib.USDC;
        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.QUOTE_BASE, 998474274, abi.encode(path), ProtocolType.V2);
    }

    function test_swapExactOutput_V2_SINGLE_QUOTE_BASE() public {
        address[] memory path = new address[](2);
        path[0] = TestLib.USDT;
        path[1] = TestLib.USDC;
        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.QUOTE_BASE, 1001528883, abi.encode(path), ProtocolType.V2);
    }

    function test_swapExactInput_V2_MULTIHOP_BASE_QUOTE() public {
        address[] memory path = new address[](3);
        path[0] = TestLib.USDC;
        path[1] = TestLib.WETH;
        path[2] = TestLib.USDT;
        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.BASE_QUOTE, 995376837, abi.encode(path), ProtocolType.V2);
    }

    function test_swapExactOutput_V2_MULTIHOP_BASE_QUOTE() public {
        address[] memory path = new address[](3);
        path[0] = TestLib.USDC;
        path[1] = TestLib.WETH;
        path[2] = TestLib.USDT;
        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.BASE_QUOTE, 1004645217, abi.encode(path), ProtocolType.V2);
    }

    function test_swapExactInput_V2_MULTIHOP_QUOTE_BASE() public {
        address[] memory path = new address[](3);
        path[0] = TestLib.USDT;
        path[1] = TestLib.WETH;
        path[2] = TestLib.USDC;

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.QUOTE_BASE, 992395816, abi.encode(path), ProtocolType.V2);
    }

    function test_swapExactOutput_V2_MULTIHOP_QUOTE_BASE() public {
        address[] memory path = new address[](3);
        path[0] = TestLib.USDT;
        path[1] = TestLib.WETH;
        path[2] = TestLib.USDC;

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.QUOTE_BASE, 1007663413, abi.encode(path), ProtocolType.V2);
    }

    function test_swapExactInput_mixed_routes_QUOTE_BASE() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.USDT, 6, "USDT");
        _deployAndApproveAdapter();

        // ** Add V2 Single route
        {
            address[] memory path = new address[](2);
            path[0] = TestLib.USDT;
            path[1] = TestLib.USDC;
            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(0, _protocolTypeToCommand(ProtocolType.V2), abi.encode(path));
        }

        // ** Add V3 Single route
        {
            uint256 fee = IUniswapV3Pool(TestLib.uniswap_v3_USDC_USDT_POOL).fee();
            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(
                1,
                _protocolTypeToCommand(ProtocolType.V3),
                abi.encodePacked(TestLib.USDT, uint24(fee), TestLib.USDC)
            );
        }

        // ** Add V4 Single route
        {
            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(
                2,
                _protocolTypeToCommand(ProtocolType.V4_SINGLE),
                abi.encode(poolKeyUSDC_USDT, false, bytes(""))
            );
        }

        // ** Add V4 Multihop route
        {
            PathKey[] memory path = new PathKey[](2);
            path[0] = PathKey(
                poolKeyETH_USDT.currency0,
                poolKeyETH_USDT.fee,
                poolKeyETH_USDT.tickSpacing,
                poolKeyETH_USDT.hooks,
                bytes("")
            ); // gives out USDT
            path[1] = PathKey(
                poolKeyETH_USDC.currency1,
                poolKeyETH_USDC.fee,
                poolKeyETH_USDC.tickSpacing,
                poolKeyETH_USDC.hooks,
                bytes("")
            ); // gives out ETH

            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(3, _protocolTypeToCommand(ProtocolType.V4_MULTIHOP), abi.encode(path));
        }

        // ** Activate mix route
        {
            uint256[] memory swapRoute = new uint256[](7);
            swapRoute[0] = 0;
            swapRoute[1] = 25e16;

            swapRoute[2] = 1;
            swapRoute[3] = 25e16;

            swapRoute[4] = 2;
            swapRoute[5] = 25e16;

            swapRoute[6] = 3;
            // activeSwapPath[7] = 25e16; The last element is not needed because it can be deduced from previous elements.

            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapRoute(true, false, swapRoute);
        }

        part_assert_exact_swap(SwapType.EXACT_INPUT, SwapDirection.QUOTE_BASE, testAmount, 999639259);
    }

    function test_swap_key() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.USDT, 6, "USDT");
        _deployAndApproveAdapter();

        assertEq(uniswapSwapAdapter.toSwapKey(true, true), 3); // exact input, base to quote
        assertEq(uniswapSwapAdapter.toSwapKey(true, false), 2); // exact input, quote to base
        assertEq(uniswapSwapAdapter.toSwapKey(false, true), 1); // exact output, base to quote
        assertEq(uniswapSwapAdapter.toSwapKey(false, false), 0); // exact output, quote to base
    }

    function test_routes_operator() public {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.USDT, 6, "USDT");
        vm.prank(deployer.addr);
        swapAdapter = new UniswapSwapAdapter(BASE, QUOTE, bDec, qDec, TestLib.UNIVERSAL_ROUTER, TestLib.PERMIT_2);

        uniswapSwapAdapter = IUniswapSwapAdapter(address(swapAdapter));
        _fakeSetComponents(address(swapAdapter), alice.addr);

        uint256 swapRouteId = 5;
        uint256[] memory activeSwapPath = new uint256[](1);
        activeSwapPath[0] = swapRouteId;

        vm.expectRevert();
        vm.prank(deployer.addr);
        uniswapSwapAdapter.setSwapPath(swapRouteId, 1, bytes(""));

        vm.expectRevert();
        vm.prank(deployer.addr);
        uniswapSwapAdapter.setSwapRoute(true, true, activeSwapPath);

        vm.startPrank(deployer.addr);
        uniswapSwapAdapter.setRoutesOperator(deployer.addr);
        uniswapSwapAdapter.setSwapPath(swapRouteId, 1, bytes(""));
        uniswapSwapAdapter.setSwapRoute(true, true, activeSwapPath);
        vm.stopPrank();
    }

    // ** Helpers

    function part_test_swap(
        SwapType swapType,
        SwapDirection direction,
        uint256 amountExpected,
        bytes memory swapRoute,
        ProtocolType protocolType
    ) internal {
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.USDT, 6, "USDT");
        _deployAndApproveAdapter();

        uint256 swapRouteId = 5;
        uint256[] memory activeSwapPath = new uint256[](1);
        activeSwapPath[0] = swapRouteId;

        vm.startPrank(deployer.addr);
        uniswapSwapAdapter.setSwapPath(swapRouteId, _protocolTypeToCommand(protocolType), swapRoute);
        uniswapSwapAdapter.setSwapRoute(
            swapType == SwapType.EXACT_INPUT,
            direction == SwapDirection.BASE_QUOTE,
            activeSwapPath
        );
        vm.stopPrank();

        part_assert_exact_swap(swapType, direction, testAmount, amountExpected);
    }

    function part_assert_exact_swap(
        SwapType swapType,
        SwapDirection direction,
        uint256 amountIn, // amountSpecified
        uint256 amountOut // amountExpected
    ) internal {
        if (swapType == SwapType.EXACT_OUTPUT) (amountIn, amountOut) = (amountOut, amountIn);
        IERC20 tokenIn = direction == SwapDirection.BASE_QUOTE ? BASE : QUOTE;

        deal(address(tokenIn), address(alice.addr), amountIn);
        assertEq(tokenIn.balanceOf(alice.addr), amountIn);
        assertEq(otherToken(tokenIn).balanceOf(alice.addr), 0);

        uint256 amount;
        vm.prank(alice.addr);

        swapType == SwapType.EXACT_INPUT
            ? amount = swapAdapter.swapExactInput(tokenIn == BASE, amountIn)
            : amount = swapAdapter.swapExactOutput(tokenIn == BASE, amountOut);

        assertEq(amount, swapType == SwapType.EXACT_INPUT ? amountOut : amountIn);
        assertEq(tokenIn.balanceOf(alice.addr), 0);
        assertEq(otherToken(tokenIn).balanceOf(alice.addr), amountOut);
    }

    function _getAndCheckPoolKey(
        IERC20 token0,
        IERC20 token1,
        uint24 fee,
        int24 tickSpacing,
        bytes32 _poolId
    ) internal pure returns (PoolKey memory poolKey) {
        poolKey = PoolKey(
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            fee,
            tickSpacing,
            IHooks(address(0))
        );
        PoolId id = poolKey.toId();
        assertEq(PoolId.unwrap(id), _poolId, "PoolId not equal");
    }

    function _deployAndApproveAdapter() internal {
        vm.prank(deployer.addr);
        swapAdapter = new UniswapSwapAdapter(BASE, QUOTE, bDec, qDec, TestLib.UNIVERSAL_ROUTER, TestLib.PERMIT_2);

        uniswapSwapAdapter = IUniswapSwapAdapter(address(swapAdapter));
        vm.prank(deployer.addr);
        uniswapSwapAdapter.setRoutesOperator(deployer.addr);
        _fakeSetComponents(address(swapAdapter), alice.addr);

        vm.prank(alice.addr);
        BASE.forceApprove(address(swapAdapter), type(uint256).max);
        vm.prank(alice.addr);
        QUOTE.forceApprove(address(swapAdapter), type(uint256).max);
    }

    function _protocolTypeToCommand(ProtocolType protocolType) internal pure returns (uint8) {
        if (protocolType == ProtocolType.V2) return 0;
        else if (protocolType == ProtocolType.V3) return 1;
        else if (protocolType == ProtocolType.V4_SINGLE) return 2;
        else if (protocolType == ProtocolType.V4_MULTIHOP) return 3;
        else revert("ProtocolType not found");
    }
}
