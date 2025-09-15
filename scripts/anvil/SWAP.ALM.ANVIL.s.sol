// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** external imports
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Commands} from "@universal-router/Commands.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {DeployUtils} from "../common/DeployUtils.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {TestLib} from "@test/libraries/TestLib.sol";

contract SwapDepositAndRebalanceALMAnvil is DeployUtils {
    using SafeERC20 for IERC20;

    function setUp() public {
        setup_network_specific_addresses_unichain();
        BASE = IERC20(UConstants.USDC);
        QUOTE = IERC20(UConstants.WETH);
        loadActorsAnvil();
        loadComponentAddresses(true);
        IS_NTS = true;
        poolKey = constructPoolKey();
    }

    function run() external {
        doSwap();
    }

    function doSwap() internal {
        // console.log("sqrtPrice before %s", hook.sqrtPriceCurrent());
        // console.log("TVL before: %s", alm.TVL(oracle.price()));

        // ** swap
        {
            vm.startBroadcast(swapperKey);
            uint256 ethToSwap = 1 ether;

            uint256 currency0Before = poolKey.currency0.balanceOf(swapperAddress);
            uint256 currency1Before = poolKey.currency1.balanceOf(swapperAddress);

            swapAndReturnDeltas(true, true, ethToSwap);

            uint256 currency0After = poolKey.currency0.balanceOf(swapperAddress);
            uint256 currency1After = poolKey.currency1.balanceOf(swapperAddress);

            console.log("currency0Delta", TestLib.absSub(currency0After, currency0Before));
            console.log("currency1Delta", TestLib.absSub(currency1After, currency1Before));

            vm.stopBroadcast();
        }

        console.log("sqrtPrice after %s", hook.sqrtPriceCurrent());
        // console.log("TVL after: %s", alm.TVL(oracle.price()));
    }

    function swapAndReturnDeltas(bool zeroForOne, bool isExactInput, uint256 amount) private {
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = getV4Input(zeroForOne, isExactInput, amount);
        inputs[1] = abi.encode(address(0), swapperAddress, 0);
        bytes memory swapCommands;
        swapCommands = bytes.concat(swapCommands, bytes(abi.encodePacked(uint8(Commands.V4_SWAP))));
        swapCommands = bytes.concat(swapCommands, bytes(abi.encodePacked(uint8(Commands.SWEEP))));

        uint256 deadline = type(uint256).max; //block.timestamp + 10 minutes;
        if (isSendETHToRouter(zeroForOne)) universalRouter.execute{value: amount}(swapCommands, inputs, deadline);
        else universalRouter.execute(swapCommands, inputs, deadline);
    }

    function isSendETHToRouter(bool zeroForOne) internal view returns (bool) {
        address token = address(zeroForOne ? Currency.unwrap(poolKey.currency0) : Currency.unwrap(poolKey.currency1));
        return token == address(ETH);
    }

    function getV4Input(bool zeroForOne, bool isExactInput, uint256 amount) private view returns (bytes memory) {
        bytes[] memory params = new bytes[](3);
        uint8 swapAction = isExactInput ? uint8(Actions.SWAP_EXACT_IN_SINGLE) : uint8(Actions.SWAP_EXACT_OUT_SINGLE);

        params[0] = abi.encode(
            // We use ExactInputSingleParams structure for both exact input and output swaps
            // since the parameter structure is identical.
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(amount), // or amountOut for ExactOutputSingleParams
                amountOutMinimum: isExactInput ? uint128(0) : type(uint128).max, // or amountInMaximum for ExactInputSingleParams
                hookData: ""
            })
        );

        params[1] = abi.encode(
            zeroForOne ? poolKey.currency0 : poolKey.currency1,
            isExactInput ? amount : type(uint256).max
        );
        params[2] = abi.encode(zeroForOne ? poolKey.currency1 : poolKey.currency0, isExactInput ? 0 : amount);

        return abi.encode(abi.encodePacked(swapAction, uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)), params);
    }
}
