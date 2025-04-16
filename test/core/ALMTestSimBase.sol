// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** v4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

// ** contracts
import {ALMTestBase} from "./ALMTestBase.sol";
import {ALMControl} from "@test/core/ALMControl.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ALMTestSimBase is ALMTestBase {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

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

    // --- Logic --- //

    function approve_accounts() public override {
        super.approve_accounts();
        vm.startPrank(swapper.addr);
        BASE.forceApprove(address(hookControl), type(uint256).max);
        QUOTE.forceApprove(address(hookControl), type(uint256).max);
        vm.stopPrank();
    }

    function approve_actor(address actor) internal {
        vm.startPrank(actor);
        BASE.forceApprove(address(hookControl), type(uint256).max);
        QUOTE.forceApprove(address(hook), type(uint256).max);

        BASE.forceApprove(address(hookControl), type(uint256).max);
        QUOTE.forceApprove(address(hookControl), type(uint256).max);
        vm.stopPrank();
    }

    function init_control_hook() internal {
        vm.startPrank(deployer.addr);

        address hookAddress = address(uint160(Hooks.AFTER_INITIALIZE_FLAG));
        deployCodeTo("ALMControl.sol", abi.encode(manager, address(hook)), hookAddress);
        hookControl = ALMControl(hookAddress);
        vm.label(address(hookControl), "hookControl");

        (address _token0, address _token1) = getTokensInOrder();
        // ** Pool deployment
        (keyControl, ) = initPool(
            Currency.wrap(_token0),
            Currency.wrap(_token1),
            hookControl,
            poolFee,
            initialSQRTPrice
        );

        vm.stopPrank();
    }

    function simulate_swap(uint256 amount, bool zeroForOne, bool _in, bool swapInControl) internal {
        int256 delta0;
        int256 delta1;
        int256 delta0c;
        int256 delta1c;
        uint160 preSqrtPriceX96 = hook.sqrtPriceCurrent();
        if (zeroForOne) {
            // ** TOKEN0 => TOKEN1
            if (_in) {
                (delta0, delta1) = __swap(true, -int256(amount), key);
                if (swapInControl) (delta0c, delta1c) = __swap(true, -int256(amount), keyControl);
            } else {
                (delta0, delta1) = __swap(true, int256(amount), key);
                if (swapInControl) (delta0c, delta1c) = __swap(true, int256(amount), keyControl);
            }
        } else {
            // ** TOKEN1 => TOKEN0
            if (_in) {
                (delta0, delta1) = __swap(false, -int256(amount), key);
                if (swapInControl) (delta0c, delta1c) = __swap(false, -int256(amount), keyControl);
            } else {
                (delta0, delta1) = __swap(false, int256(amount), key);
                if (swapInControl) (delta0c, delta1c) = __swap(false, int256(amount), keyControl);
            }
        }

        // Make oracle change with swap price
        vm.mockCall(address(hook.oracle()), abi.encodeWithSelector(IOracle.price.selector), abi.encode(getHookPrice()));

        // @Notice: doing save swap data here to remove stack too deep error
        {
            string[] memory inputs = new string[](3);
            inputs[0] = "node";
            inputs[1] = "test/simulations/logSwap.js";
            inputs[2] = toHexString(
                abi.encodePacked(
                    amount,
                    zeroForOne,
                    _in,
                    block.number,
                    delta0,
                    delta1,
                    delta0c,
                    delta1c,
                    preSqrtPriceX96,
                    hook.sqrtPriceCurrent()
                )
            );
            vm.ffi(inputs);
        }

        // ** Make oracle change with swap price
        alignOraclesAndPools(hook.sqrtPriceCurrent());
    }

    function _rebalanceOrError(uint256 s) internal returns (bool success) {
        try rebalanceAdapter.rebalance(s) {
            return true;
        } catch {
            return false;
        }
    }

    // --- Save state helpers --- //

    function save_pool_state() internal {
        uint128 liquidity = hook.liquidity();
        uint160 sqrtPriceX96 = hook.sqrtPriceCurrent();

        int24 tickLower = hook.tickLower();
        int24 tickUpper = hook.tickUpper();
        assertApproxEqAbs(tickLower, hookControl.tickLower(), 1);
        assertApproxEqAbs(tickUpper, hookControl.tickUpper(), 1);

        uint256 CL = lendingAdapter.getCollateralLong();
        uint256 CS = lendingAdapter.getCollateralShort();
        uint256 DL = lendingAdapter.getBorrowedLong();
        uint256 DS = lendingAdapter.getBorrowedShort();

        uint256 tvl = hook.TVL();
        uint256 tvlControl = hookControl.TVL();
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
            CL,
            CS,
            DL,
            DS,
            tvl,
            tvlControl,
            sharePrice,
            sharePriceControl
        );
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/logState.js";
        inputs[2] = toHexString(packedData);
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

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/logDeposits.js";
        inputs[2] = toHexString(packedData);
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

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/logWithdraws.js";
        inputs[2] = toHexString(packedData);
        vm.ffi(inputs);
    }

    function save_rebalance_data(uint256 priceThreshold, uint256 auctionTriggerTime) internal {
        uint128 liquidity = hook.liquidity();
        bytes memory packedData = abi.encodePacked(liquidity, priceThreshold, auctionTriggerTime, block.number);

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/logRebalance.js";
        inputs[2] = toHexString(packedData);
        vm.ffi(inputs);
    }

    // --- Generation helpers

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

    function addressFromSeed(uint256 seed) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(seed)))));
    }

    // -- Simulation helpers --
    function random(uint256 randomCap) public returns (uint) {
        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "test/simulations/random.js";
        inputs[2] = toHexString(abi.encodePacked(randomCap));

        bytes memory result = vm.ffi(inputs);
        return abi.decode(result, (uint256));
    }

    function rollOneBlock() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12);
    }

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
}
