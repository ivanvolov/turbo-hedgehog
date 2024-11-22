// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ALMTestBase} from "./ALMTestBase.sol";
import {ALMControl} from "@test/core/ALMControl.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

abstract contract ALMTestSimBase is ALMTestBase {
    using CurrencyLibrary for Currency;

    ALMControl hookControl;
    PoolKey keyControl;

    uint256 depositProbabilityPerBlock;
    uint256 maxUniqueDepositors;
    uint256 maxDeposits;
    uint256 depositorReuseProbability;

    uint256 withdrawProbabilityPerBlock;
    uint256 maxWithdraws;
    uint256 numberOfSwaps;
    uint256 expectedPoolPriceForConversion;

    function init_control_hook() internal {
        vm.startPrank(deployer.addr);

        // MARK: Usual UniV4 hook deployment process
        address hookAddress = address(uint160(Hooks.AFTER_INITIALIZE_FLAG));
        deployCodeTo("ALMControl.sol", abi.encode(manager, address(hook)), hookAddress);
        hookControl = ALMControl(hookAddress);
        vm.label(address(hookControl), "hookControl");

        // ** Pool deployment
        (keyControl, ) = initPool(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(WETH)),
            hookControl,
            poolFee,
            initialSQRTPrice,
            ""
        );
        // MARK END

        vm.stopPrank();
    }

    function save_pool_state() internal {
        uint128 liquidity = hook.liquidity();
        uint160 sqrtPriceX96 = hook.sqrtPriceCurrent();
        int24 tickLower = hook.tickLower();
        int24 tickUpper = hook.tickUpper();
        assertApproxEqAbs(tickLower, hookControl.tickLower(), 1);
        assertApproxEqAbs(tickUpper, hookControl.tickUpper(), 1);

        uint256 borrowed = lendingAdapter.getBorrowed();
        uint256 supplied = lendingAdapter.getSupplied();
        uint256 collateral = lendingAdapter.getCollateral();
        uint256 tvl = hook.TVL();
        uint256 tvlControl = hookControl.TVL();
        // console.log("tvl", tvl);
        // console.log("tvlControl", tvlControl);
        uint256 sharePrice = hook.sharePrice();
        uint256 sharePriceControl = hookControl.sharePrice();

        (uint160 sqrtPriceX96Control, ) = hookControl.getTick();

        bytes memory packedData = abi.encodePacked(
            block.number,
            sqrtPriceX96Control,
            liquidity,
            sqrtPriceX96,
            tickLower,
            tickUpper,
            borrowed,
            supplied,
            collateral,
            tvl,
            tvlControl,
            sharePrice,
            sharePriceControl
        );
        string memory packedHexString = toHexString(packedData);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/logState.js";
        inputs[2] = packedHexString;
        vm.ffi(inputs);
    }

    function save_swap_data(
        uint256 amount,
        bool zeroForOne,
        bool _in,
        int256 delta0,
        int256 delta1,
        int256 delta0c,
        int256 delta1c
    ) internal {
        bytes memory packedData = abi.encodePacked(
            amount,
            zeroForOne,
            _in,
            block.number,
            delta0,
            delta1,
            delta0c,
            delta1c
        );
        string memory packedHexString = toHexString(packedData);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/logSwap.js";
        inputs[2] = packedHexString;
        vm.ffi(inputs);
    }

    function clear_snapshots() internal {
        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "test/simulations/clear.js";
        vm.ffi(inputs);
    }

    function save_deposit_data(
        uint256 amount,
        address actor,
        uint256 delWETH,
        uint256 delWETHcontrol,
        uint256 delUSDCcontrol,
        uint256 delShares,
        uint256 delSharesControl
    ) internal {
        bytes memory packedData = abi.encodePacked(
            amount,
            address(actor),
            block.number,
            delWETH,
            delWETHcontrol,
            delUSDCcontrol,
            delShares,
            delSharesControl
        );
        string memory packedHexString = toHexString(packedData);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/logDeposits.js";
        inputs[2] = packedHexString;
        vm.ffi(inputs);
    }

    function save_withdraw_data(
        uint256 shares1,
        uint256 shares2,
        address actor,
        uint256 delWETH,
        uint256 delUSDC,
        uint256 delWETHcontrol,
        uint256 delUSDCcontrol
    ) internal {
        bytes memory packedData = abi.encodePacked(
            shares1,
            shares2,
            address(actor),
            block.number,
            delWETH,
            delUSDC,
            delWETHcontrol,
            delUSDCcontrol
        );
        string memory packedHexString = toHexString(packedData);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/logWithdraws.js";
        inputs[2] = packedHexString;
        vm.ffi(inputs);
    }

    function save_rebalance_data(int24 delta) internal {
        bytes memory packedData = abi.encodePacked(delta, block.number);
        string memory packedHexString = toHexString(packedData);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/logRebalance.js";
        inputs[2] = packedHexString;
        vm.ffi(inputs);
    }

    function random(uint256 randomCap) public returns (uint) {
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/random.js";
        inputs[2] = toHexString(abi.encodePacked(randomCap));

        bytes memory result = vm.ffi(inputs);
        return abi.decode(result, (uint256));
    }

    // -- Simulation helpers --

    function toHexString(bytes memory input) public pure returns (string memory) {
        require(input.length < type(uint256).max / 2 - 1);
        bytes16 symbols = "0123456789abcdef";
        bytes memory hex_buffer = new bytes(2 * input.length + 2);
        hex_buffer[0] = "0";
        hex_buffer[1] = "x";

        uint pos = 2;
        uint256 length = input.length;
        for (uint i = 0; i < length; ++i) {
            uint _byte = uint8(input[i]);
            hex_buffer[pos++] = symbols[_byte >> 4];
            hex_buffer[pos++] = symbols[_byte & 0xf];
        }
        return string(hex_buffer);
    }

    uint256 lastGeneratedAddressId;

    uint256 offset = 100;

    function resetGenerator() public {
        lastGeneratedAddressId = 0;
    }

    function chooseDepositor() public returns (address) {
        if (maxUniqueDepositors == lastGeneratedAddressId) return getDepositorToReuse();

        uint256 _random = random(100);
        if (_random <= depositorReuseProbability && lastGeneratedAddressId > 0) {
            // reuse existing address
            return getDepositorToReuse();
        } else {
            // generate new address
            lastGeneratedAddressId = lastGeneratedAddressId + 1;
            address actor = getDepositorById(lastGeneratedAddressId);
            approve_actor(actor);
            return actor;
        }
    }

    function getDepositorToReuse() public returns (address) {
        if (lastGeneratedAddressId == 0) return address(0); // This means no addresses were generated yet
        return getDepositorById(random(lastGeneratedAddressId));
    }

    function getDepositorById(uint256 id) public view returns (address) {
        return addressFromSeed(offset + id);
    }

    function approve_actor(address actor) internal {
        vm.startPrank(actor);
        WETH.approve(address(hook), type(uint256).max);
        WETH.approve(address(hook), type(uint256).max);

        WETH.approve(address(hookControl), type(uint256).max);
        USDC.approve(address(hookControl), type(uint256).max);
        vm.stopPrank();
    }

    function addressFromSeed(uint256 seed) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(seed)))));
    }
}
