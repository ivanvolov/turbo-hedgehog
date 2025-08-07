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

        // ETH/USDT, ETH/USDC, WETH/USDT, WETH/USDC
        call_all_combinations(priceStable * 1e18, priceLongTail * 1e18, int256(6 - 18));
        call_all_combinations(priceStable * 1e8, priceLongTail * 1e8, int256(6 - 18));

        // ETH/DAI, WETH/DAI
        call_all_combinations(priceStable * 1e18, priceLongTail * 1e18, int256(18 - 18));
        call_all_combinations(priceStable * 1e8, priceLongTail * 1e8, int256(18 - 18));

        // CBBTC/USDT, CBBTC/USDC, WBTC/USDT, WBTC/USDC
        call_all_combinations(priceStable * 1e18, priceLongTail * 1e18, int256(6 - 8));
        call_all_combinations(priceStable * 1e8, priceLongTail * 1e8, int256(6 - 8));

        // CBBTC/DAI, CBBTC/DAI, WBTC/DAI, WBTC/DAI
        call_all_combinations(priceStable * 1e18, priceLongTail * 1e18, int256(18 - 8));
        call_all_combinations(priceStable * 1e8, priceLongTail * 1e8, int256(18 - 8));
    }

    /// @dev Test STABLE-STABLE pair.
    function test_Fuzz_STABLE_STABLE_TAIL(uint256 priceStable0, uint256 priceStable1) public {
        priceStable0 = bound(priceStable0, STABLE_MIN, STABLE_MAX);
        priceStable1 = bound(priceStable1, STABLE_MIN, STABLE_MAX);

        // USDC/USDT, USDT/USDC
        call_all_combinations(priceStable0 * 1e8, priceStable0 * 1e8, int256(0));
        call_all_combinations(priceStable0 * 1e18, priceStable0 * 1e18, int256(0));

        // USDC/DAI, USDT/DAI, DAI/USDC, DAI/USDT
        call_all_combinations(priceStable0 * 1e18, priceStable1 * 1e18, int256(18 - 6));
        call_all_combinations(priceStable0 * 1e8, priceStable1 * 1e8, int256(18 - 6));
    }

    /// @dev Test LONG_TAIL-LONG_TAIL pair.
    function test_Fuzz_LONG_TAIL_LONG_TAIL(uint256 priceLongTail0, uint256 priceLongTail1) public {
        priceLongTail0 = bound(priceLongTail0, LONG_TAIL_MIN, LONG_TAIL_MAX);
        priceLongTail1 = bound(priceLongTail1, LONG_TAIL_MIN, LONG_TAIL_MAX);

        // ETH/WSTETH, WSTETH/ETH
        call_all_combinations(priceLongTail0 * 1e18, priceLongTail1 * 1e18, int256(0));
        call_all_combinations(priceLongTail0 * 1e8, priceLongTail1 * 1e8, int256(0));

        // WSTETH/ZERO_FEED, ZERO_FEED/WSTETH
        call_all_combinations(priceLongTail0 * 1e18, 1e18, int256(18));
        call_all_combinations(priceLongTail0 * 1e8, 1e18, int256(18)); // Zero feed always returns 18 decimals.
    }

    function call_all_combinations(uint256 price0, uint256 price1, int256 totalDecDel) public {
        TestLib.newOracleGetPrices(price0, price1, totalDecDel, false);
        TestLib.newOracleGetPrices(price0, price1, -totalDecDel, false);
        TestLib.newOracleGetPrices(price0, price1, totalDecDel, true);
        TestLib.newOracleGetPrices(price0, price1, -totalDecDel, true);

        TestLib.newOracleGetPrices(price1, price0, totalDecDel, false);
        TestLib.newOracleGetPrices(price1, price0, -totalDecDel, false);
        TestLib.newOracleGetPrices(price1, price0, totalDecDel, true);
        TestLib.newOracleGetPrices(price1, price0, -totalDecDel, true);
    }

    // ** Helpers

    function _select_mainnet_fork(uint256 block_number) internal {
        select_mainnet_fork(block_number);
        _create_accounts();
        manager = MConstants.manager;
    }
}
