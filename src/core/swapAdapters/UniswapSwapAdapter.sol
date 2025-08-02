// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** v4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IV4Router, PathKey} from "v4-periphery/src/interfaces/IV4Router.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

// ** External imports
import {mulDiv18 as mul18} from "@prb-math/Common.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Commands} from "@universal-router/Commands.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniversalRouter} from "@universal-router/IUniversalRouter.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {ISwapAdapter} from "../../interfaces/swapAdapters/ISwapAdapter.sol";

/// @title Uniswap Swap Adapter
/// @notice Provides swap functionality for Uniswap V2, V3, and V4 using Uniswap UniversalRouterV2.
contract UniswapSwapAdapter is Base, ISwapAdapter {
    error InvalidSwapRoute();
    error InvalidProtocolType();
    error NotRoutesOperator(address account);
    error RouteNotFound(bool isBaseToQuote, bool isExactInput);

    event RoutesOperatorSet(address indexed routesOperator);
    event SwapPathSet(uint256 indexed swapRouteId, uint8 indexed protocolType, bytes input);
    event SwapRouteSet(uint8 indexed swapKey, uint256[] swapRoute);

    using SafeERC20 for IERC20;

    IUniversalRouter public immutable router;
    IPermit2 public immutable permit2;
    address public routesOperator;
    IWETH9 public immutable WETH9;

    struct SwapPath {
        uint8 protocolType;
        bytes input;
    }

    mapping(uint256 => SwapPath) public swapPaths;
    mapping(uint8 => uint256[]) public swapRoutes;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        IUniversalRouter _router,
        IPermit2 _permit2,
        IWETH9 _weth
    ) Base(ComponentType.EXTERNAL_ADAPTER, msg.sender, _base, _quote) {
        router = _router;
        permit2 = _permit2;
        WETH9 = _weth;

        BASE.forceApprove(address(permit2), type(uint256).max);
        permit2.approve(address(BASE), address(router), type(uint160).max, type(uint48).max);

        QUOTE.forceApprove(address(permit2), type(uint256).max);
        permit2.approve(address(QUOTE), address(router), type(uint160).max, type(uint48).max);
    }

    function setRoutesOperator(address _routesOperator) external onlyOwner {
        routesOperator = _routesOperator;
        emit RoutesOperatorSet(_routesOperator);
    }

    /**
     * @notice Sets the swap route for a given swap key based on input/output and base/quote direction.
     * @param isExactInput Indicates whether the swap is for an exact input amount (true) or an exact output amount (false).
     * @param isBaseToQuote Indicates the direction of the swap: true for base-to-quote, false for quote-to-base.
     * @param _swapRoute An array representing path IDs and their corresponding multipliers.
     * For example, [1, 35e18, 3] means 35% of the amount is routed through path 1 and the remaining 65% through path 3.
     * The array must have an odd number of elements, where even indices are path IDs and odd indices are multipliers (in 1e18 precision).
     */
    function setSwapRoute(
        bool isExactInput,
        bool isBaseToQuote,
        uint256[] calldata _swapRoute
    ) external onlyRoutesOperator {
        if (_swapRoute.length % 2 == 0) revert InvalidSwapRoute();

        uint8 swapKey = toSwapKey(isExactInput, isBaseToQuote);
        swapRoutes[swapKey] = _swapRoute;
        emit SwapRouteSet(swapKey, _swapRoute);
    }

    /**
     * @notice Sets the swap path details for a given swap path ID.
     * @dev Defines the protocol and input data used for a specific swap path.
     * @param _swapPathId The unique identifier for the swap path.
     * @param _protocolType The protocol type to use:
     * 0 = Uniswap V2, 1 = Uniswap V3, 2 = Uniswap V4 (single swap), 3 = Uniswap V4 (multihop swap).
     * @param _input Encoded input data required by the specified protocol for the swap path.
     */
    function setSwapPath(uint256 _swapPathId, uint8 _protocolType, bytes calldata _input) external onlyRoutesOperator {
        swapPaths[_swapPathId] = SwapPath({protocolType: _protocolType, input: _input});
        emit SwapPathSet(_swapPathId, _protocolType, _input);
    }

    function swapExactInput(bool isBaseToQuote, uint256 amountIn) external onlyModule returns (uint256 amountOut) {
        console.log("> START: swapExactInput");
        console.log("isBaseToQuote %s", isBaseToQuote);
        console.log("amountIn %s", amountIn);
        if (amountIn == 0) return 0;
        IERC20 tokenIn = isBaseToQuote ? BASE : QUOTE;
        IERC20 tokenOut = isBaseToQuote ? QUOTE : BASE;

        console.log("tokenIn", address(tokenIn));
        console.log("tokenOut", address(tokenOut));
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        executeSwap(isBaseToQuote, true, amountIn);

        amountOut = tokenOut.balanceOf(address(this));
        tokenOut.safeTransfer(msg.sender, amountOut);
        console.log("> END: swapExactInput");
    }

    function swapExactOutput(bool isBaseToQuote, uint256 amountOut) external onlyModule returns (uint256 amountIn) {
        console.log("> START:swapExactOutput");
        console.log("isBaseToQuote %s", isBaseToQuote);
        console.log("amountOut %s", amountOut);

        if (amountOut == 0) return 0;
        IERC20 tokenIn = isBaseToQuote ? BASE : QUOTE;
        IERC20 tokenOut = isBaseToQuote ? QUOTE : BASE;

        console.log("tokenIn", address(tokenIn));
        console.log("tokenOut", address(tokenOut));
        amountIn = tokenIn.balanceOf(msg.sender);
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        executeSwap(isBaseToQuote, false, amountOut);

        tokenOut.safeTransfer(msg.sender, amountOut);

        uint256 amountExtra = tokenIn.balanceOf(address(this));
        if (amountExtra > 0) {
            tokenIn.safeTransfer(msg.sender, amountExtra);
            amountIn -= amountExtra;
        }
        console.log("> END: swapExactOutput");
    }

    function executeSwap(bool isBaseToQuote, bool isExactInput, uint256 amountTarget) internal {
        bytes memory swapCommands;
        uint256[] memory route = swapRoutes[toSwapKey(isExactInput, isBaseToQuote)];
        if (route.length == 0) revert RouteNotFound(isBaseToQuote, isExactInput);

        bytes[] memory inputs = new bytes[]((route.length + 1) / 2 + 1);
        uint256 amountTargetLeft = amountTarget;
        for (uint256 i = 0; i < route.length + 1; ) {
            SwapPath memory path = swapPaths[route[i]];
            if (path.protocolType > 3) revert InvalidProtocolType();
            uint256 nextAmount = route.length == i + 1 ? amountTargetLeft : mul18(amountTarget, route[i + 1]);

            uint8 nextCommand;
            if (path.protocolType == 0) {
                nextCommand = isExactInput ? uint8(Commands.V2_SWAP_EXACT_IN) : uint8(Commands.V2_SWAP_EXACT_OUT);
                inputs[i / 2] = _getV2Input(isExactInput, nextAmount, path.input);
            } else if (path.protocolType == 1) {
                nextCommand = isExactInput ? uint8(Commands.V3_SWAP_EXACT_IN) : uint8(Commands.V3_SWAP_EXACT_OUT);
                inputs[i / 2] = _getV3Input(isExactInput, nextAmount, path.input);
            } else {
                nextCommand = uint8(Commands.V4_SWAP);
                inputs[i / 2] = _getV4Input(
                    isBaseToQuote,
                    isExactInput,
                    path.protocolType == 3,
                    nextAmount,
                    path.input
                );
            }
            swapCommands = bytes.concat(swapCommands, bytes(abi.encodePacked(nextCommand)));
            amountTargetLeft -= nextAmount;

            unchecked {
                i += 2;
            }
        }

        // Always SWEEP extra ETH from router to adapter.
        swapCommands = bytes.concat(swapCommands, bytes(abi.encodePacked(uint8(Commands.SWEEP))));
        inputs[inputs.length - 1] = abi.encode(address(0), address(this), 0);

        uint256 ethBalance = address(this).balance;
        console.log("ethBalance %s", ethBalance);
        console.log("> START: router.execute");
        router.execute{value: ethBalance}(swapCommands, inputs, block.timestamp);
        console.log("> END: router.execute");

        // If routers returns ETH, we need to wrap it.
        ethBalance = address(this).balance;
        console.log("ethBalance after %s", ethBalance);

        if (ethBalance > 0) WETH9.deposit{value: ethBalance}();
    }

    function _getV2Input(bool isExactInput, uint256 amount, bytes memory route) internal view returns (bytes memory) {
        address[] memory path = abi.decode(route, (address[]));
        return abi.encode(address(this), amount, isExactInput ? 0 : type(uint256).max, path, true);
    }

    function _getV3Input(bool isExactInput, uint256 amount, bytes memory path) internal view returns (bytes memory) {
        return abi.encode(address(this), amount, isExactInput ? 0 : type(uint256).max, path, true);
    }

    function _getV4Input(
        bool isBaseToQuote,
        bool isExactInput,
        bool isMultihop,
        uint256 amount,
        bytes memory route
    ) internal returns (bytes memory) {
        console.log("> START: _getV4Input");
        bytes[] memory params = new bytes[](3);
        uint8 swapAction;
        bool unwrapBefore;

        if (isMultihop) {
            console.log("> isMultihop");
            PathKey[] memory path;
            // IERC20 currencyIn;
            (unwrapBefore, path) = abi.decode(route, (bool, PathKey[]));
            swapAction = isExactInput ? uint8(Actions.SWAP_EXACT_IN) : uint8(Actions.SWAP_EXACT_OUT);
            console.log("AMOUNT %s", amount);
            console.log("isBaseToQuote %s", isBaseToQuote);

            // Currency cur = adjustForEth(isBaseToQuote == true ? BASE : QUOTE);
            Currency cur = adjustForEth(isBaseToQuote == isExactInput ? BASE : QUOTE);
            if (isExactInput) console.log("currencyIn:", Currency.unwrap(cur));
            else console.log("currencyOut:", Currency.unwrap(cur));
            params[0] = abi.encode(
                // We use ExactInputParams structure for both exact input and output swaps
                // since the parameter structure is identical.
                IV4Router.ExactInputParams({
                    currencyIn: cur, // or currencyOut for ExactOutputParams
                    path: path,
                    amountIn: uint128(amount), // or amountOut for ExactOutputParams
                    amountOutMinimum: isExactInput ? uint128(0) : type(uint128).max // or amountInMaximum for ExactOutputParams
                })
            );
        } else {
            console.log("> !isMultihop");
            PoolKey memory key;
            bool zeroForOne;
            bytes memory hookData;
            (unwrapBefore, key, zeroForOne, hookData) = abi.decode(route, (bool, PoolKey, bool, bytes));
            swapAction = isExactInput ? uint8(Actions.SWAP_EXACT_IN_SINGLE) : uint8(Actions.SWAP_EXACT_OUT_SINGLE);

            params[0] = abi.encode(
                // We use ExactInputSingleParams structure for both exact input and output swaps
                // since the parameter structure is identical.
                IV4Router.ExactInputSingleParams({
                    poolKey: key,
                    zeroForOne: zeroForOne,
                    amountIn: uint128(amount), // or amountOut for ExactOutputSingleParams
                    amountOutMinimum: isExactInput ? uint128(0) : type(uint128).max, // or amountInMaximum for ExactInputSingleParams
                    hookData: hookData
                })
            );
        }

        if (unwrapBefore) isExactInput ? WETH9.withdraw(amount) : WETH9.withdraw(WETH9.balanceOf(address(this)));

        params[1] = abi.encode(adjustForEth(isBaseToQuote ? BASE : QUOTE), isExactInput ? amount : type(uint256).max);
        params[2] = abi.encode(adjustForEth(isBaseToQuote ? QUOTE : BASE), isExactInput ? 0 : amount);

        return abi.encode(abi.encodePacked(swapAction, uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)), params);
    }

    function adjustForEth(IERC20 token) internal view returns (Currency) {
        if (address(token) == address(WETH9)) return Currency.wrap(address(0));
        return Currency.wrap(address(token));
    }

    receive() external payable {
        //TODO: restrict by UNIVERSAL_ROUTER
        // Intentionally empty as the contract need to receive ETH from V4 router.
    }

    // ** Helpers

    function toSwapKey(bool isExactInput, bool isBaseToQuote) public pure returns (uint8) {
        return (isExactInput ? 2 : 0) + (isBaseToQuote ? 1 : 0);
    }

    // ** Modifiers

    modifier onlyRoutesOperator() {
        if (msg.sender != routesOperator) revert NotRoutesOperator(msg.sender);
        _;
    }
}
