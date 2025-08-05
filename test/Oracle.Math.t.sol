// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {AggregatorV3Interface as IAggV3} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ABDKMath64x64} from "@test/libraries/math/ABDKMath64x64.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {Constants as BConstants} from "@test/libraries/constants/BaseConstants.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {ud} from "@prb-math/UD60x18.sol";
import {mulDiv, mulDiv18 as mul18, sqrt} from "@prb-math/Common.sol";

contract OracleMathTest is ALMTestBase {
    function setUp() public {
        _select_mainnet_fork(23059745);
    }

    /// @notice
    /// 1. `isInvertedAssets` is used in all asset-related operations:
    ///     - Deposits are made in either the Base or Quote asset.
    ///     - Withdrawals are made from either the Long or Short side.
    ///     - Rebalancing is done to either Base or Quote depending on this flag.
    ///
    /// 2. `isInvertedPool` indicates whether the pool direction is inverted:
    ///     - Pools are expected to follow the `Quote:Base` format.
    ///     - If `isInvertedPool == true`, the format is `Base:Quote`.
    ///     - This flag must be considered wherever currency and token are used together.
    ///     - ist. BASE:QUOTE = true, QUOTE:BASE = false

    // TODO: check all of them have reversed order.
    function test_strategies_oracles_mainnet() public {
        console.log("\n> ETH_USDC");
        {
            part_compare_oracle_with_v4_pool(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDC,
                true,
                int8(18 - 6),
                ETH_USDC_key
            );
            console.log("");
            part_compare_oracle_with_v4_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_WETH,
                false,
                int8(6 - 18),
                ETH_USDC_key
            );
        }

        console.log("\n> USDC_WETH");
        {
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_WETH,
                true,
                int8(6 - 18),
                MConstants.uniswap_v3_USDC_WETH_POOL
            );
            console.log("");
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDC,
                false,
                int8(18 - 6),
                MConstants.uniswap_v3_USDC_WETH_POOL
            );
        }

        console.log("\n> ETH_USDT");
        {
            part_compare_oracle_with_v4_pool(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDT,
                true,
                int8(18 - 6),
                ETH_USDT_key
            );
            console.log("");
            part_compare_oracle_with_v4_pool(
                MConstants.chainlink_feed_USDT,
                MConstants.chainlink_feed_WETH,
                false,
                int8(6 - 18),
                ETH_USDT_key
            );
        }

        console.log("\n> WETH_USDT");
        {
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDT,
                MConstants.chainlink_feed_WETH,
                false,
                int8(6 - 18),
                MConstants.uniswap_v3_WETH_USDT_POOL
            );
            console.log("");
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDT,
                true,
                int8(18 - 6),
                MConstants.uniswap_v3_WETH_USDT_POOL
            );
        }

        console.log("\n> USDC_USDT");
        {
            part_compare_oracle_with_v4_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_USDT,
                true,
                int8(6 - 6),
                USDC_USDT_key
            );
            console.log("V3poolSQRT", getV3PoolSQRTPrice(MConstants.uniswap_v3_USDC_USDT_POOL));
            console.log("");
            part_compare_oracle_with_v4_pool(
                MConstants.chainlink_feed_USDT,
                MConstants.chainlink_feed_USDC,
                false,
                int8(6 - 6),
                USDC_USDT_key
            );
            console.log("V3poolSQRT", getV3PoolSQRTPrice(MConstants.uniswap_v3_USDC_USDT_POOL));
        }

        console.log("\n> USDC_CBBTC");
        {
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_CBBTC,
                true,
                int8(6 - 8),
                MConstants.uniswap_v3_USDC_CBBTC_POOL
            );
            console.log("");
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_CBBTC,
                MConstants.chainlink_feed_USDC,
                false,
                int8(8 - 6),
                MConstants.uniswap_v3_USDC_CBBTC_POOL
            );
        }

        console.log("\n> DAI_USDC");
        {
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_DAI,
                false,
                int8(6 - 18),
                MConstants.uniswap_v3_DAI_USDC_POOL
            );
            console.log("");
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_DAI,
                MConstants.chainlink_feed_USDC,
                true,
                int8(18 - 6),
                MConstants.uniswap_v3_DAI_USDC_POOL
            );
        }
    }

    // TODO: add price comparison for all of them.
    function test_strategies_oracles_unichain() public {
        _select_unichain_fork(23567130);
        console.log("\n> ETH_WSTETH with one feed");
        {
            mock_latestRoundData(UConstants.chronicle_feed_WSTETH, 1210060639502791600);
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_WSTETH,
                UConstants.zero_feed,
                false,
                int8(-18),
                ETH_WSTETH_key_unichain
            );
        }

        _select_unichain_fork(23302675);
        console.log("\n> ETH_USDC");
        {
            mock_latestRoundData(UConstants.chronicle_feed_WETH, 3634568623200000000000);
            mock_latestRoundData(UConstants.chronicle_feed_USDC, 999820000000000000);
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_USDC,
                UConstants.chronicle_feed_WETH,
                false,
                int8(6 - 18),
                ETH_USDC_key_unichain
            );
        }

        _select_unichain_fork(23128176);
        console.log("\n> ETH_USDT");
        {
            mock_latestRoundData(UConstants.chronicle_feed_WETH, 3754570000000000000000);
            mock_latestRoundData(UConstants.chronicle_feed_USDT, 999983595619733749);
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_USDT,
                UConstants.chronicle_feed_WETH,
                false,
                int8(6 - 18),
                ETH_USDC_key_unichain
            );
        }

        _select_unichain_fork(23404999);
        console.log("\n> USDC_USDT");
        {
            mock_latestRoundData(UConstants.chronicle_feed_USDT, 999620000000000000);
            mock_latestRoundData(UConstants.chronicle_feed_USDC, 999735368664584522);
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_USDC,
                UConstants.chronicle_feed_USDT,
                true,
                int8(0),
                USDC_USDT_key_unichain
            );
        }
    }

    function test_strategies_oracles_base() public {
        _select_base_fork(33774814);
        console.log("\n> USDC_CBBTC");
        {
            part_compare_oracle_with_v4_pool(
                BConstants.chainlink_feed_USDC,
                BConstants.chainlink_feed_CBBTC,
                true,
                int8(6 - 8),
                USDC_CBBTC_key_base
            );
        }
    }

    function test_other_possible_oracles() public {
        _select_mainnet_fork(23075773);
        console.log("\n> WSTETH_WETH with one feed");
        {
            // Warning: WSTETH_WETH only exist on V3 mainnet, but WSTETH/WETH feed exist only on Unichain. This test does not make much sense.
            mock_latestRoundData(UConstants.chronicle_feed_WSTETH, 1210148407573673000);
            part_compare_oracle_with_v3_pool(
                UConstants.chronicle_feed_WSTETH, // Yes, this is a wrong network contract address byt we mock it, should be fine.
                MConstants.zero_feed,
                true,
                int256(-18),
                MConstants.uniswap_v3_WSTETH_WETH_POOL
            );
        }
    }

    // ** Fuzzers

    // TODO: read WTF is fuzzing and what is the coverage.
    /// @notice Chronicle feeds are always 18. Api3 always have 18 decimals. https://docs.api3.org/dapps/integration/contract-integration.html#using-value.
    ///         Chainlink feeds are 8 for USDT, USDC, DAI, ETH, BTC, WBTC, CBBTC, WSTETH.

    /// @dev Tests WSTETH-WETH and ETH-WSTETH with one feed.
    function test_Fuzz_WSTETH_ETH_Chronicle_Api3_Chainlink(uint256 priceWSTETH) public view {
        uint256 quote_MIN = 5e17; // 0.5ETH for WSTETH.
        uint256 quote_MAX = 100e18; //  1000ETH USDT.
        priceWSTETH = bound(priceWSTETH, quote_MIN, quote_MAX);

        // We will construct totalDecDel = 0 in one feed oracle.
        TestLib.newOracleGetPrices(priceWSTETH, 1e18, int256(0), true);
        TestLib.newOracleGetPrices(1e18, priceWSTETH, int256(0), true);
    }

    /// @dev Tests ETH/USDC, USDC/ETH, ETH/USDT, USDT/ETH for for both V4 and V3 oracles (with native and not).
    function test_Fuzz_ETH_USDC_T_Chronicle_Api3_Chainlink(uint256 priceUSD, uint256 priceETH) public view {
        uint256 base_MIN = 1e17; // 0.1$ for USDC/T.
        uint256 base_MAX = 100e18; //  100$ for USDC/T.
        uint256 quote_MIN = 1e17; // 0.1$ for ETH/WETH.
        uint256 quote_MAX = 10 * 10e6 * 1e18; //  10kk ETH/WETH.
        priceUSD = bound(priceUSD, base_MIN, base_MAX);
        priceETH = bound(priceETH, quote_MIN, quote_MAX);

        // Chronicle and API3 feeds are always 18. So 18-18 = 0. The chainlink have 8 on these examples.
        int256 totalDecDel = int8(6 - 18);
        TestLib.newOracleGetPrices(priceUSD, priceETH, totalDecDel, false);
        TestLib.newOracleGetPrices(priceUSD, priceETH, totalDecDel, true);
        TestLib.newOracleGetPrices(priceETH, priceUSD, -totalDecDel, true);
        TestLib.newOracleGetPrices(priceETH, priceUSD, -totalDecDel, false);
    }

    /// @dev Tests USDT/CBBTC, CBBTC/USDT, USDC/CBBTC, CBBTC/USDC,
    ///      USDT/WBTC, WBTC/USDT, USDC/WBTC, WBTC/USDC.
    function test_Fuzz_BTC_USD_Chronicle_Api3_Chainlink(uint256 priceUSD, uint256 priceBTC) public view {
        uint256 base_MIN = 1e17; // 0.1$ for USDT/C.
        uint256 base_MAX = 100e18; //  100$ for USDT/C.
        uint256 quote_MIN = 1e17; // 0.1$ for CBBTC/WBTC.
        uint256 quote_MAX = 100 * 10e6 * 1e18; //  100kk CBBTC.
        priceUSD = bound(priceUSD, base_MIN, base_MAX);
        priceBTC = bound(priceBTC, quote_MIN, quote_MAX);

        // Chronicle and API3 feeds are always 18. So 18-18 = 0. The chainlink have 8 on these examples.
        int256 totalDecDel = int8(8 - 6);
        TestLib.newOracleGetPrices(priceBTC, priceUSD, totalDecDel, false);
        TestLib.newOracleGetPrices(priceBTC, priceUSD, totalDecDel, true); // just in case.
        TestLib.newOracleGetPrices(priceUSD, priceBTC, -totalDecDel, true);
        TestLib.newOracleGetPrices(priceUSD, priceBTC, -totalDecDel, false); // just in case.
    }

    /// @dev Tests USDC/DAI, DAI/USDC, USDT/DAI, DAI/USDT.
    function test_Fuzz_DAI_USDC_T_Chronicle_Api3_Chainlink(uint256 priceUSD, uint256 priceDAI) public view {
        uint256 base_MIN = 1e17; // 0.1$ for USDT/C.
        uint256 base_MAX = 100e18; //  100$ for USDT/C.
        uint256 quote_MIN = 1e17; // 0.1$ for DAI.
        uint256 quote_MAX = 100e18; //  100$ DAI.
        priceUSD = bound(priceUSD, base_MIN, base_MAX);
        priceDAI = bound(priceDAI, quote_MIN, quote_MAX);

        // Chronicle and API3 feeds are always 18. So 18-18 = 0. The chainlink have 8 on these examples.
        int256 totalDecDel = int8(18 - 6);
        TestLib.newOracleGetPrices(priceDAI, priceUSD, totalDecDel, true);
        TestLib.newOracleGetPrices(priceDAI, priceUSD, totalDecDel, false); // just in case.
        TestLib.newOracleGetPrices(priceUSD, priceDAI, -totalDecDel, false);
        TestLib.newOracleGetPrices(priceUSD, priceDAI, -totalDecDel, true); // just in case.
    }

    /// @dev Tests USDC/USDT, USDT/USDC.
    function test_Fuzz_USDT_USDC_Chronicle_Api3_Chainlink(uint256 priceUSDC, uint256 priceUSDT) public view {
        uint256 base_MIN = 1e17; // 0.1$ for USDC.
        uint256 base_MAX = 100e18; //  100$ for USDC.
        uint256 quote_MIN = 1e17; // 0.1$ for USDT.
        uint256 quote_MAX = 100e18; //  100$ USDT.
        priceUSDC = bound(priceUSDC, base_MIN, base_MAX);
        priceUSDT = bound(priceUSDT, quote_MIN, quote_MAX);

        // Chronicle and API3 feeds are always 18. So 18-18 = 0. The chainlink have 8 on these examples.
        int256 totalDecDel = int8(6 - 6);
        TestLib.newOracleGetPrices(priceUSDT, priceUSDC, totalDecDel, false);
        TestLib.newOracleGetPrices(priceUSDC, priceUSDT, totalDecDel, true);
    }

    // ** Constraints

    //TODO: Retest this constraints in sim. ALMMathLib.getSqrtPriceX96FromPrice(340256786833063481322211904572563530436318729319284211712);
    //TODO: Think about scaleFactor constraints, do wee need them? No we don't.

    // ** Helpers

    function part_compare_oracle_with_v4_pool(
        IAggV3 feedB,
        IAggV3 feedQ,
        bool isInvertedPool,
        int256 tokenDecDelta,
        PoolKey memory poolKey
    ) public {
        print_oracle_answer(feedB, feedQ, isInvertedPool, tokenDecDelta);
        console.log("poolSQRT  ", getV4PoolSQRTPrice(poolKey));
    }

    function part_compare_oracle_with_v3_pool(
        IAggV3 feedB,
        IAggV3 feedQ,
        bool isInvertedPool,
        int256 tokenDecDelta,
        address pool
    ) public {
        print_oracle_answer(feedB, feedQ, isInvertedPool, tokenDecDelta);
        console.log("poolSQRT  ", getV3PoolSQRTPrice(pool));
    }

    function print_oracle_answer(IAggV3 feedB, IAggV3 feedQ, bool isInvertedPool, int256 tokenDecDel) private {
        (uint256 priceO, uint256 sqrtPriceO) = getOldOracleAnswer(feedB, feedQ, isInvertedPool, tokenDecDel);
        console.log("sqrtPriceO", sqrtPriceO);
        (uint256 priceN, uint256 sqrtPriceN) = create_oracle_and_get_price(feedB, feedQ, isInvertedPool, tokenDecDel);
        console.log("sqrtPriceN", sqrtPriceN);
    }

    function create_oracle_and_get_price(
        IAggV3 feedB,
        IAggV3 feedQ,
        bool isInvertedPool,
        int256 tokenDecDelta
    ) public returns (uint256 _price, uint160 _sqrtPriceX96) {
        IOracle mock_oracle = __create_oracle(feedB, feedQ, 24 hours, 24 hours, isInvertedPool, int8(tokenDecDelta));
        return mock_oracle.poolPrice();
    }

    function getOldOracleAnswer(
        IAggV3 feedB,
        IAggV3 feedQ,
        bool isInvertedPool,
        int256 tokenDecDelta
    ) public view returns (uint256 _price, uint160 _sqrtPriceX96) {
        int256 totalDecDel = _calcTotalDecDelta(tokenDecDelta, feedB, feedQ);
        uint256 priceB = address(feedB) == address(0) ? 1e18 : getFeedPrice(feedB);
        uint256 priceQ = address(feedQ) == address(0) ? 1e18 : getFeedPrice(feedQ);
        return TestLib.oldOracleGetPrices(priceB, priceQ, totalDecDel, isInvertedPool);
    }

    function _calcTotalDecDelta(int256 _tokenDecDel, IAggV3 _feedBase, IAggV3 _feedQuote) public view returns (int256) {
        // console.log(">> calcTotalDecDelta");
        int256 feedBDec = address(_feedBase) == address(0) ? int256(0) : int256(int8(_feedBase.decimals()));
        int256 feedQDec = address(_feedQuote) == address(0) ? int256(0) : int256(int8(_feedQuote.decimals()));
        // console.logInt(_tokenDecDel + feedBDec - feedQDec);
        return _tokenDecDel + feedBDec - feedQDec;
    }

    // ** Get Forks

    function _select_mainnet_fork(uint256 block_number) internal {
        select_mainnet_fork(block_number);
        _create_accounts();
        manager = MConstants.manager;
    }

    function _select_unichain_fork(uint256 block_number) internal {
        select_unichain_fork(block_number);
        _create_accounts();
        manager = UConstants.manager;
    }

    function _select_base_fork(uint256 block_number) internal {
        select_base_fork(block_number);
        _create_accounts();
        manager = BConstants.manager;
    }
}
