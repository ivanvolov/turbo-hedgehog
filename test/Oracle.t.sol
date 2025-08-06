// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IOracleTest, IChronicleSelfKisser} from "@test/interfaces/IOracleTest.sol";

contract OracleFuzzing is ALMTestBase {
    function setUp() public {
        _select_mainnet_fork(23059745);
    }
    // ** Fuzzers

    /// @notice Chronicle feeds are always 18. Api3 always have 18 decimals. https://docs.api3.org/dapps/integration/contract-integration.html#using-value.
    ///         Chainlink feeds are 8 for USDT, USDC, DAI, ETH, BTC, WBTC, CBBTC, WSTETH.
    ///         So the feedBDec - feedQDec = 0 in these cases.

    uint256 constant STABLE_MIN = 1; // 0.01$ for STABLE.
    uint256 constant STABLE_MAX = 10000; //  100$ for STABLE.

    uint256 constant LONG_TAIL_MIN = 1; // 1$ for LONG-TAIL.
    uint256 constant LONG_TAIL_MAX = 10e6; // 10kk$ for LONG-TAIL.

    /// @dev Test STABLE-LONG-TAIL pair.
    function test_Fuzz_STABLE_LONG_TAIL(uint256 priceStable, uint256 priceLongTail) public {
        priceStable = bound(priceStable, STABLE_MIN, STABLE_MAX);
        priceLongTail = bound(priceLongTail, LONG_TAIL_MIN, LONG_TAIL_MAX);
        part_stable_long_tail(priceStable, priceLongTail, false);
    }

    /// @dev Test STABLE-STABLE pair.
    function test_Fuzz_STABLE_STABLE_TAIL(uint256 priceStable0, uint256 priceStable1) public {
        priceStable0 = bound(priceStable0, STABLE_MIN, STABLE_MAX);
        priceStable1 = bound(priceStable1, STABLE_MIN, STABLE_MAX);
        part_stable_stable_tail(priceStable0, priceStable1, false);
    }

    /// @dev Test LONG_TAIL-LONG_TAIL pair.
    function test_Fuzz_LONG_TAIL_LONG_TAIL(uint256 priceLongTail0, uint256 priceLongTail1) public {
        priceLongTail0 = bound(priceLongTail0, LONG_TAIL_MIN, LONG_TAIL_MAX);
        priceLongTail1 = bound(priceLongTail1, LONG_TAIL_MIN, LONG_TAIL_MAX);
        part_long_tail_long_tail(priceLongTail0, priceLongTail1, false);
    }

    /// @dev Simulate STABLE-LONG_TAIL pair.
    function test_simulate_stable_long_tail() public {
        clear_snapshots();
        uint256 stableSTEP = 1000;
        uint256 longTailSTEP = 100000;
        for (uint256 pS = STABLE_MIN; pS <= STABLE_MAX; pS += stableSTEP) {
            for (uint256 pLT = LONG_TAIL_MIN; pLT <= LONG_TAIL_MAX; pLT += longTailSTEP) {
                part_stable_long_tail(pS, pLT, true);
            }
        }
    }

    function part_stable_long_tail(uint256 priceStable, uint256 priceLongTail, bool isSimulation) public {
        // ETH/USDT, ETH/USDC, WETH/USDT, WETH/USDC
        call_all_combinations(priceStable * 1e18, priceLongTail * 1e18, int256(6 - 18), isSimulation);
        call_all_combinations(priceStable * 1e8, priceLongTail * 1e8, int256(6 - 18), isSimulation);

        // ETH/DAI, WETH/DAI
        call_all_combinations(priceStable * 1e18, priceLongTail * 1e18, int256(18 - 18), isSimulation);
        call_all_combinations(priceStable * 1e8, priceLongTail * 1e8, int256(18 - 18), isSimulation);

        // CBBTC/USDT, CBBTC/USDC, WBTC/USDT, WBTC/USDC
        call_all_combinations(priceStable * 1e18, priceLongTail * 1e18, int256(6 - 8), isSimulation);
        call_all_combinations(priceStable * 1e8, priceLongTail * 1e8, int256(6 - 8), isSimulation);

        // CBBTC/DAI, CBBTC/DAI, WBTC/DAI, WBTC/DAI
        call_all_combinations(priceStable * 1e18, priceLongTail * 1e18, int256(18 - 8), isSimulation);
        call_all_combinations(priceStable * 1e8, priceLongTail * 1e8, int256(18 - 8), isSimulation);
    }

    function part_stable_stable_tail(uint256 priceStable0, uint256 priceStable1, bool isSimulation) public {
        // USDC/USDT, USDT/USDC
        call_all_combinations(priceStable0 * 1e8, priceStable0 * 1e8, int256(0), isSimulation);
        call_all_combinations(priceStable0 * 1e18, priceStable0 * 1e18, int256(0), isSimulation);

        // USDC/DAI, USDT/DAI, DAI/USDC, DAI/USDT
        call_all_combinations(priceStable0 * 1e18, priceStable1 * 1e18, int256(18 - 6), isSimulation);
        call_all_combinations(priceStable0 * 1e8, priceStable1 * 1e8, int256(18 - 6), isSimulation);
    }

    function part_long_tail_long_tail(uint256 priceLongTail0, uint256 priceLongTail1, bool isSimulation) public {
        // ETH/WSTETH, WSTETH/ETH
        call_all_combinations(priceLongTail0 * 1e18, priceLongTail1 * 1e18, int256(0), isSimulation);
        call_all_combinations(priceLongTail0 * 1e8, priceLongTail1 * 1e8, int256(0), isSimulation);

        // WSTETH/ZERO_FEED, ZERO_FEED/WSTETH
        call_all_combinations(priceLongTail0 * 1e18, 1e18, int256(18), isSimulation);
        call_all_combinations(priceLongTail0 * 1e8, 1e18, int256(18), isSimulation); // Zero feed always returns 18 decimals.
    }

    function call_all_combinations(
        uint256 priceStable,
        uint256 priceLongTail,
        int256 totalDecDel,
        bool isSimulation
    ) public {
        calc_and_record(priceStable, priceLongTail, totalDecDel, false, isSimulation ? 1 : 0);
        calc_and_record(priceStable, priceLongTail, -totalDecDel, false, isSimulation ? 2 : 0);
        calc_and_record(priceStable, priceLongTail, totalDecDel, true, isSimulation ? 3 : 0);
        calc_and_record(priceStable, priceLongTail, -totalDecDel, true, isSimulation ? 4 : 0);

        calc_and_record(priceLongTail, priceStable, totalDecDel, false, isSimulation ? 5 : 0);
        calc_and_record(priceLongTail, priceStable, -totalDecDel, false, isSimulation ? 6 : 0);
        calc_and_record(priceLongTail, priceStable, totalDecDel, true, isSimulation ? 7 : 0);
        calc_and_record(priceLongTail, priceStable, -totalDecDel, true, isSimulation ? 8 : 0);
    }

    // ** Helpers

    function calc_and_record(
        uint256 priceBase,
        uint256 priceQuote,
        int256 totalDecDel,
        bool isInvertedPool,
        uint256 testCase
    ) public {
        (uint256 p, uint160 sqrt) = TestLib.newOracleGetPrices(priceBase, priceQuote, totalDecDel, isInvertedPool);

        if (testCase != 0) {
            bytes memory packedData = abi.encodePacked(
                priceBase,
                priceQuote,
                totalDecDel,
                isInvertedPool,
                p,
                sqrt,
                testCase
            );

            string[] memory inputs = new string[](3);
            inputs[0] = "node";
            inputs[1] = "test/simulations/logOracle.js";
            inputs[2] = toHexString(packedData);
            vm.ffi(inputs);
        }
    }

    function clear_snapshots() internal {
        string[] memory inputs = new string[](2);
        inputs[0] = "node";
        inputs[1] = "test/simulations/clear.js";
        vm.ffi(inputs);
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

    function _select_mainnet_fork(uint256 block_number) internal {
        select_mainnet_fork(block_number);
        _create_accounts();
        manager = MConstants.manager;
    }
}
