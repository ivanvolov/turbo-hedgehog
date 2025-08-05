// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapSwapAdapter} from "@src/interfaces/swapAdapters/IUniswapSwapAdapter.sol";
import {IUniswapV3Pool} from "@v3-core/IUniswapV3Pool.sol";
import {PathKey} from "v4-periphery/src/interfaces/IV4Router.sol";

contract SwapAdapterTest is ALMTestBase {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    IUniswapSwapAdapter uniswapSwapAdapter;

    enum SwapDirection {
        BASE_QUOTE,
        QUOTE_BASE
    }
    enum SwapType {
        EXACT_INPUT,
        EXACT_OUTPUT
    }

    function setUp() public {
        select_mainnet_fork(22490362);

        vm.label(address(ETH), "ETH");
        vm.label(MConstants.USDC, "USDC");
        vm.label(MConstants.USDT, "USDT");

        testAmount = 1000e6;
    }

    uint256 testAmount;

    function test_swap_eth_ExactInput_V4_SINGLE_BASE_QUOTE() public {
        BASE = IERC20(MConstants.WETH);
        QUOTE = IERC20(MConstants.USDT);
        _create_accounts();
        testAmount = 1e18;

        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.BASE_QUOTE,
            2529699535,
            abi.encode(true, ETH_USDT_key, true, bytes("")),
            ProtId.V4_SINGLE
        );
    }

    function test_swap_eth_ExactOutput_V4_SINGLE_BASE_QUOTE() public {
        BASE = IERC20(MConstants.WETH);
        QUOTE = IERC20(MConstants.USDT);
        _create_accounts();
        testAmount = 2529699535;

        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.BASE_QUOTE,
            999999999619294475,
            abi.encode(true, ETH_USDT_key, true, bytes("")),
            ProtId.V4_SINGLE
        );
    }

    function test_swap_eth_ExactInput_V4_SINGLE_QUOTE_BASE() public {
        BASE = IERC20(MConstants.WETH);
        QUOTE = IERC20(MConstants.USDT);
        _create_accounts();
        testAmount = 2529699535;

        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.QUOTE_BASE,
            998306944672183526,
            abi.encode(false, ETH_USDT_key, false, bytes("")),
            ProtId.V4_SINGLE
        );
    }

    function test_swap_eth_ExactOutput_V4_SINGLE_QUOTE_BASE() public {
        BASE = IERC20(MConstants.WETH);
        QUOTE = IERC20(MConstants.USDT);
        _create_accounts();
        testAmount = 1e18;

        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.QUOTE_BASE,
            2533991212,
            abi.encode(false, ETH_USDT_key, false, bytes("")),
            ProtId.V4_SINGLE
        );
    }

    function test_swapExactInput_V4_SINGLE_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.BASE_QUOTE,
            999621885,
            abi.encode(false, USDC_USDT_key, true, bytes("")),
            ProtId.V4_SINGLE
        );
    }

    function test_swapExactOutput_V4_SINGLE_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.BASE_QUOTE,
            1000378259,
            abi.encode(false, USDC_USDT_key, true, bytes("")),
            ProtId.V4_SINGLE
        );
    }

    function test_swapExactInput_V4_SINGLE_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.QUOTE_BASE,
            1000176859,
            abi.encode(false, USDC_USDT_key, false, bytes("")),
            ProtId.V4_SINGLE
        );
    }

    function test_swapExactOutput_V4_SINGLE_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.QUOTE_BASE,
            999823173,
            abi.encode(false, USDC_USDT_key, false, bytes("")),
            ProtId.V4_SINGLE
        );
    }

    function test_swapExactInput_V4_MULTIHOP_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey(
            ETH_USDC_key.currency0, // Intermediate token is ETH
            ETH_USDC_key.fee,
            ETH_USDC_key.tickSpacing,
            ETH_USDC_key.hooks,
            abi.encodePacked(uint8(1))
        );
        path[1] = PathKey(
            ETH_USDT_key.currency1, // Intermediate token is USDT
            ETH_USDT_key.fee,
            ETH_USDT_key.tickSpacing,
            ETH_USDT_key.hooks,
            abi.encodePacked(uint8(2))
        );

        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.BASE_QUOTE,
            998357409,
            abi.encode(false, path),
            ProtId.V4_MULTIHOP
        );
    }

    function test_swapExactOutput_V4_MULTIHOP_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey(
            ETH_USDC_key.currency1, // Intermediate token is USDC, the tokenIn.
            ETH_USDC_key.fee,
            ETH_USDC_key.tickSpacing,
            ETH_USDC_key.hooks,
            abi.encodePacked(uint8(1))
        );
        path[1] = PathKey(
            ETH_USDT_key.currency0, // Intermediate token is ETH, the intermediate token.
            ETH_USDT_key.fee,
            ETH_USDT_key.tickSpacing,
            ETH_USDT_key.hooks,
            abi.encodePacked(uint8(2))
        );
        // this gos backwards

        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.BASE_QUOTE,
            1001645736,
            abi.encode(false, path),
            ProtId.V4_MULTIHOP
        );
    }

    function test_swapExactInput_V4_MULTIHOP_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey(
            ETH_USDT_key.currency0, // Intermediate token is ETH, the intermediate token.
            ETH_USDT_key.fee,
            ETH_USDT_key.tickSpacing,
            ETH_USDT_key.hooks,
            bytes("")
        );
        path[1] = PathKey(
            ETH_USDC_key.currency1, // Intermediate token is USDC, the tokenOut.
            ETH_USDC_key.fee,
            ETH_USDC_key.tickSpacing,
            ETH_USDC_key.hooks,
            bytes("")
        );

        part_test_swap(
            SwapType.EXACT_INPUT,
            SwapDirection.QUOTE_BASE,
            999107408,
            abi.encode(false, path),
            ProtId.V4_MULTIHOP
        );
    }

    //TODO: it's here should fail, why not?. Test all with ETH.
    function test_swapExactOutput_V4_MULTIHOP_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey(
            ETH_USDT_key.currency1, // Intermediate token is USDT
            ETH_USDT_key.fee,
            ETH_USDT_key.tickSpacing,
            ETH_USDT_key.hooks,
            bytes("")
        );
        path[1] = PathKey(
            ETH_USDC_key.currency0, // Intermediate token is ETH
            ETH_USDC_key.fee,
            ETH_USDC_key.tickSpacing,
            ETH_USDC_key.hooks,
            bytes("")
        );
        // this goes backwards

        part_test_swap(
            SwapType.EXACT_OUTPUT,
            SwapDirection.QUOTE_BASE,
            1000893629,
            abi.encode(false, path),
            ProtId.V4_MULTIHOP
        );
    }

    function test_swapExactInput_V3_SINGLE_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        uint256 fee = IUniswapV3Pool(MConstants.uniswap_v3_USDC_USDT_POOL).fee();
        bytes memory path = abi.encodePacked(MConstants.USDC, uint24(fee), MConstants.USDT);

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.BASE_QUOTE, 999607371, path, ProtId.V3);
    }

    function test_swapExactOutput_V3_SINGLE_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        uint256 fee = IUniswapV3Pool(MConstants.uniswap_v3_USDC_USDT_POOL).fee();
        bytes memory path = abi.encodePacked(MConstants.USDT, uint24(fee), MConstants.USDC);

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.BASE_QUOTE, 1000392784, path, ProtId.V3);
    }

    function test_swapExactInput_V3_SINGLE_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        uint256 fee = IUniswapV3Pool(MConstants.uniswap_v3_USDC_USDT_POOL).fee();
        bytes memory path = abi.encodePacked(MConstants.USDT, uint24(fee), MConstants.USDC);

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.QUOTE_BASE, 1000192674, path, ProtId.V3);
    }

    function test_swapExactOutput_V3_SINGLE_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        uint256 fee = IUniswapV3Pool(MConstants.uniswap_v3_USDC_USDT_POOL).fee();
        bytes memory path = abi.encodePacked(MConstants.USDC, uint24(fee), MConstants.USDT);

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.QUOTE_BASE, 999807364, path, ProtId.V3);
    }

    function test_swapExactInput_V3_MULTIHOP_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        bytes memory path = abi.encodePacked(
            MConstants.USDC,
            uint24(IUniswapV3Pool(MConstants.uniswap_v3_USDC_WETH_POOL).fee()),
            address(MConstants.WETH),
            uint24(IUniswapV3Pool(MConstants.uniswap_v3_WETH_USDT_POOL).fee()),
            MConstants.USDT
        );

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.BASE_QUOTE, 996166709, path, ProtId.V3);
    }

    function test_swapExactOutput_V3_MULTIHOP_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        bytes memory path = abi.encodePacked(
            MConstants.USDT,
            uint24(IUniswapV3Pool(MConstants.uniswap_v3_WETH_USDT_POOL).fee()),
            address(MConstants.WETH),
            uint24(IUniswapV3Pool(MConstants.uniswap_v3_USDC_WETH_POOL).fee()),
            MConstants.USDC
        );

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.BASE_QUOTE, 1003848075, path, ProtId.V3);
    }

    function test_swapExactInput_V3_MULTIHOP_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        bytes memory path = abi.encodePacked(
            MConstants.USDT,
            uint24(IUniswapV3Pool(MConstants.uniswap_v3_WETH_USDT_POOL).fee()),
            address(MConstants.WETH),
            uint24(IUniswapV3Pool(MConstants.uniswap_v3_USDC_WETH_POOL).fee()),
            MConstants.USDC
        );

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.QUOTE_BASE, 996819823, path, ProtId.V3);
    }

    function test_swapExactOutput_V3_MULTIHOP_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        bytes memory path = abi.encodePacked(
            MConstants.USDC,
            uint24(IUniswapV3Pool(MConstants.uniswap_v3_USDC_WETH_POOL).fee()),
            address(MConstants.WETH),
            uint24(IUniswapV3Pool(MConstants.uniswap_v3_WETH_USDT_POOL).fee()),
            MConstants.USDT
        );

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.QUOTE_BASE, 1003190350, path, ProtId.V3);
    }

    function test_swapExactInput_V2_SINGLE_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        address[] memory path = new address[](2);
        path[0] = MConstants.USDC;
        path[1] = MConstants.USDT;
        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.BASE_QUOTE, 994454813, abi.encode(path), ProtId.V2);
    }

    function test_swapExactOutput_V2_SINGLE_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        address[] memory path = new address[](2);
        path[0] = MConstants.USDC;
        path[1] = MConstants.USDT;
        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.BASE_QUOTE, 1005579129, abi.encode(path), ProtId.V2);
    }

    function test_swapExactInput_V2_SINGLE_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        address[] memory path = new address[](2);
        path[0] = MConstants.USDT;
        path[1] = MConstants.USDC;
        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.QUOTE_BASE, 998474274, abi.encode(path), ProtId.V2);
    }

    function test_swapExactOutput_V2_SINGLE_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        address[] memory path = new address[](2);
        path[0] = MConstants.USDT;
        path[1] = MConstants.USDC;
        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.QUOTE_BASE, 1001528883, abi.encode(path), ProtId.V2);
    }

    function test_swapExactInput_V2_MULTIHOP_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        address[] memory path = new address[](3);
        path[0] = MConstants.USDC;
        path[1] = MConstants.WETH;
        path[2] = MConstants.USDT;
        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.BASE_QUOTE, 995376837, abi.encode(path), ProtId.V2);
    }

    function test_swapExactOutput_V2_MULTIHOP_BASE_QUOTE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        address[] memory path = new address[](3);
        path[0] = MConstants.USDC;
        path[1] = MConstants.WETH;
        path[2] = MConstants.USDT;
        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.BASE_QUOTE, 1004645217, abi.encode(path), ProtId.V2);
    }

    function test_swapExactInput_V2_MULTIHOP_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        address[] memory path = new address[](3);
        path[0] = MConstants.USDT;
        path[1] = MConstants.WETH;
        path[2] = MConstants.USDC;

        part_test_swap(SwapType.EXACT_INPUT, SwapDirection.QUOTE_BASE, 992395816, abi.encode(path), ProtId.V2);
    }

    function test_swapExactOutput_V2_MULTIHOP_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        address[] memory path = new address[](3);
        path[0] = MConstants.USDT;
        path[1] = MConstants.WETH;
        path[2] = MConstants.USDC;

        part_test_swap(SwapType.EXACT_OUTPUT, SwapDirection.QUOTE_BASE, 1007663413, abi.encode(path), ProtId.V2);
    }

    function test_swapExactInput_mixed_routes_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        _deployAndApproveAdapter();

        // ** Add V2 Single route
        {
            address[] memory path = new address[](2);
            path[0] = MConstants.USDT;
            path[1] = MConstants.USDC;
            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(0, protToC(ProtId.V2), abi.encode(path));
        }

        // ** Add V3 Single route
        {
            uint256 fee = IUniswapV3Pool(MConstants.uniswap_v3_USDC_USDT_POOL).fee();
            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(
                1,
                protToC(ProtId.V3),
                abi.encodePacked(MConstants.USDT, uint24(fee), MConstants.USDC)
            );
        }

        // ** Add V4 Single route
        {
            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(
                2,
                protToC(ProtId.V4_SINGLE),
                abi.encode(false, USDC_USDT_key, false, bytes(""))
            );
        }

        // ** Add V4 Multihop route
        {
            PathKey[] memory path = new PathKey[](2);
            path[0] = PathKey(
                ETH_USDT_key.currency0,
                ETH_USDT_key.fee,
                ETH_USDT_key.tickSpacing,
                ETH_USDT_key.hooks,
                bytes("")
            );
            path[1] = PathKey(
                ETH_USDC_key.currency1,
                ETH_USDC_key.fee,
                ETH_USDC_key.tickSpacing,
                ETH_USDC_key.hooks,
                bytes("")
            );

            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(3, protToC(ProtId.V4_MULTIHOP), abi.encode(false, path));
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

    function test_swapExactOutput_mixed_routes_QUOTE_BASE() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        _deployAndApproveAdapter();

        // ** Add V2 Single route
        {
            address[] memory path = new address[](2);
            path[0] = MConstants.USDT;
            path[1] = MConstants.USDC;
            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(0, protToC(ProtId.V2), abi.encode(path));
        }

        // ** Add V3 Single route
        {
            uint256 fee = IUniswapV3Pool(MConstants.uniswap_v3_USDC_USDT_POOL).fee();
            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(
                1,
                protToC(ProtId.V3),
                abi.encodePacked(MConstants.USDC, uint24(fee), MConstants.USDT)
            );
        }

        // ** Add V4 Single route
        {
            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(
                2,
                protToC(ProtId.V4_SINGLE),
                abi.encode(false, USDC_USDT_key, false, bytes(""))
            );
        }

        // ** Add V4 Multihop route
        {
            PathKey[] memory path = new PathKey[](2);
            path[0] = PathKey(
                ETH_USDT_key.currency1,
                ETH_USDT_key.fee,
                ETH_USDT_key.tickSpacing,
                ETH_USDT_key.hooks,
                bytes("")
            );
            path[1] = PathKey(
                ETH_USDC_key.currency0,
                ETH_USDC_key.fee,
                ETH_USDC_key.tickSpacing,
                ETH_USDC_key.hooks,
                bytes("")
            );

            vm.prank(deployer.addr);
            uniswapSwapAdapter.setSwapPath(3, protToC(ProtId.V4_MULTIHOP), abi.encode(false, path));
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
            uniswapSwapAdapter.setSwapRoute(false, false, swapRoute);
        }

        part_assert_exact_swap(SwapType.EXACT_OUTPUT, SwapDirection.QUOTE_BASE, testAmount, 1000361243);
    }

    function test_swap_key() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        _deployAndApproveAdapter();

        assertEq(uniswapSwapAdapter.toSwapKey(true, true), 3); // exact input, base to quote
        assertEq(uniswapSwapAdapter.toSwapKey(true, false), 2); // exact input, quote to base
        assertEq(uniswapSwapAdapter.toSwapKey(false, true), 1); // exact output, base to quote
        assertEq(uniswapSwapAdapter.toSwapKey(false, false), 0); // exact output, quote to base
    }

    function test_routes_operator() public {
        create_accounts_and_tokens(MConstants.USDC, 6, "USDC", MConstants.USDT, 6, "USDT");
        vm.prank(deployer.addr);
        swapAdapter = new UniswapSwapAdapter(
            BASE,
            QUOTE,
            MConstants.UNIVERSAL_ROUTER,
            MConstants.PERMIT_2,
            MConstants.WETH9
        );

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
        ProtId protocolType
    ) internal {
        _deployAndApproveAdapter();

        uint256 swapRouteId = 5;
        uint256[] memory activeSwapPath = new uint256[](1);
        activeSwapPath[0] = swapRouteId;

        vm.startPrank(deployer.addr);
        uniswapSwapAdapter.setSwapPath(swapRouteId, protToC(protocolType), swapRoute);
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

    function _deployAndApproveAdapter() internal {
        vm.prank(deployer.addr);
        swapAdapter = new UniswapSwapAdapter(
            BASE,
            QUOTE,
            MConstants.UNIVERSAL_ROUTER,
            MConstants.PERMIT_2,
            MConstants.WETH9
        );

        uniswapSwapAdapter = IUniswapSwapAdapter(address(swapAdapter));
        vm.prank(deployer.addr);
        uniswapSwapAdapter.setRoutesOperator(deployer.addr);
        _fakeSetComponents(address(swapAdapter), alice.addr);

        vm.prank(alice.addr);
        BASE.forceApprove(address(swapAdapter), type(uint256).max);
        vm.prank(alice.addr);
        QUOTE.forceApprove(address(swapAdapter), type(uint256).max);
    }
}
