// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ABDKMath64x64} from "@test/libraries/math/ABDKMath64x64.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {ud} from "@prb-math/UD60x18.sol";
import {mulDiv, mulDiv18 as mul18, sqrt} from "@prb-math/Common.sol";

contract OracleMathTest is ALMTestBase {
    PoolKey public ETH_USDC_key;
    PoolKey public ETH_USDT_key;
    PoolKey public ETH_WSTETH_key;
    PoolKey public ETH_WSTETH_key_unichain;

    function setUp() public {
        select_mainnet_fork(23059745);
        _create_accounts();

        ETH_USDC_key = _getAndCheckPoolKey(
            IERC20(address(0)),
            IERC20(MConstants.USDC),
            500,
            10,
            0x21c67e77068de97969ba93d4aab21826d33ca12bb9f565d8496e8fda8a82ca27
        );

        ETH_USDT_key = _getAndCheckPoolKey(
            IERC20(address(0)),
            IERC20(MConstants.USDT),
            500,
            10,
            0x72331fcb696b0151904c03584b66dc8365bc63f8a144d89a773384e3a579ca73
        );

        ETH_WSTETH_key = _getAndCheckPoolKey(
            IERC20(address(0)),
            IERC20(0xc02fE7317D4eb8753a02c35fe019786854A92001),
            100,
            1,
            0xd10d359f50ba8d1e0b6c30974a65bf06895fba4bf2b692b2c75d987d3b6b863d
        );

        ETH_WSTETH_key_unichain = _getAndCheckPoolKey(
            IERC20(address(0)),
            IERC20(UConstants.WSTETH),
            100,
            1,
            0xd10d359f50ba8d1e0b6c30974a65bf06895fba4bf2b692b2c75d987d3b6b863d
        );

        manager = MConstants.manager;
    }

    /// @notice
    /// 1. `_isInvertedAssets` is used in all asset-related operations:
    ///     - Deposits are made in either the Base or Quote asset.
    ///     - Withdrawals are made from either the Long or Short side.
    ///     - Rebalancing is done to either Base or Quote depending on this flag.
    ///
    /// 2. `_isInvertedPool` indicates whether the pool direction is inverted:
    ///     - Pools are expected to follow the `Quote:Base` format.
    ///     - If `_isInvertedPool == true`, the format is `Base:Quote`.
    ///     - This flag must be considered wherever currency and token are used together.

    function test_strategy_oracles_chainlink() public {
        IOracle mock_oracle;

        console.log("\n> ETH-USDC V4");
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

        console.log("\n> ETH-USDT V4");
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

        console.log("\n> DN/ETHALM");
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

        console.log("\n> ETH-R-ALM/ETH-R2-ALM");
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

        console.log("\n> BTCALMTest");
        {
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_cbBTC,
                true,
                int8(6 - 8),
                MConstants.uniswap_v3_USDC_cbBTC_POOL
            );
            console.log("");
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_cbBTC,
                MConstants.chainlink_feed_USDC,
                false,
                int8(8 - 6),
                MConstants.uniswap_v3_USDC_cbBTC_POOL
            );
        }

        console.log("\n> UNICORD-R");
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

        console.log("\n> UNICORD");
        {
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_USDT,
                true,
                int8(0),
                MConstants.uniswap_v3_USDC_USDT_POOL
            );
            console.log("");
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDT,
                MConstants.chainlink_feed_USDC,
                false,
                int8(0),
                MConstants.uniswap_v3_USDC_USDT_POOL
            );
        }

        console.log("\n> WSTETH-WETH V3 with one feed");
        {
            uint256 priceBase = 1e18;
            uint256 priceQuote = 1210060639502791600;
            (uint256 priceO, uint256 sqrtPriceO) = oracleGetPrices(priceQuote, priceBase, int256(0), true);
            (uint256 priceN, uint256 sqrtPriceN) = newOracleGetPrices(priceQuote, priceBase, int256(0), true);

            console.log("priceO", priceO);
            console.log("priceN", priceN);
            console.log(" price", uint256(828080831151776512));
            console.log("sqrtPriceO", sqrtPriceO);
            console.log("sqrtPriceN", sqrtPriceN);
            uint256 poolSQRT = getV3PoolSQRTPrice(MConstants.uniswap_v3_WSTETH_WETH_POOL);
            console.log("poolSQRT  ", poolSQRT);
        }

        // Feed only exist on unichain, so need to re-setup the test to get the real time oracle data.
        select_unichain_fork(23567130);
        _create_accounts();
        manager = UConstants.manager;
        console.log("\n> ETH-WSTETH V4 with one feed");
        {
            uint256 priceBase = 1e18;
            uint256 priceQuote = 1210060639502791600;
            (uint256 priceO, uint256 sqrtPriceO) = oracleGetPrices(priceBase, priceQuote, int256(0), true);
            (uint256 priceN, uint256 sqrtPriceN) = newOracleGetPrices(priceBase, priceQuote, int256(0), true);

            console.log("priceO", priceO);
            console.log("priceN", priceN);
            console.log(" price", uint256(1210060639502791424));
            console.log("sqrtPriceO", sqrtPriceO);
            console.log("sqrtPriceN", sqrtPriceN);
            uint256 poolSQRT = getV4PoolSQRTPrice(ETH_WSTETH_key_unichain);
            console.log("poolSQRT  ", poolSQRT);
        }
    }

    // TODO: read WTF is fuzzing and what is the coverage.
    /// @notice Chronicle feeds are always 18. Api3 always have 18 decimals. https://docs.api3.org/dapps/integration/contract-integration.html#using-value.
    ///         Chainlink feeds are 8 for USDT, USDC, DAI, ETH, BTC, WBTC, CBBTC, WSTETH.

    /// @dev Tests WSTETH-WETH and ETH-WSTETH with one feed.
    function test_Fuzz_WSTETH_ETH_Chronicle_Api3_Chainlink(uint256 priceWSTETH) public view {
        uint256 quote_MIN = 5e17; // 0.5ETH for WSTETH.
        uint256 quote_MAX = 100e18; //  1000ETH USDT.
        priceWSTETH = bound(priceWSTETH, quote_MIN, quote_MAX);

        // We will construct totalDecDel = 0 in one feed oracle.
        newOracleGetPrices(priceWSTETH, 1e18, int256(0), true);
        newOracleGetPrices(1e18, priceWSTETH, int256(0), true);
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
        newOracleGetPrices(priceUSD, priceETH, totalDecDel, false);
        newOracleGetPrices(priceUSD, priceETH, totalDecDel, true);
        newOracleGetPrices(priceETH, priceUSD, -totalDecDel, true);
        newOracleGetPrices(priceETH, priceUSD, -totalDecDel, false);
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
        newOracleGetPrices(priceBTC, priceUSD, totalDecDel, false);
        newOracleGetPrices(priceBTC, priceUSD, totalDecDel, true); // just in case.
        newOracleGetPrices(priceUSD, priceBTC, -totalDecDel, true);
        newOracleGetPrices(priceUSD, priceBTC, -totalDecDel, false); // just in case.
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
        newOracleGetPrices(priceDAI, priceUSD, totalDecDel, true);
        newOracleGetPrices(priceDAI, priceUSD, totalDecDel, false); // just in case.
        newOracleGetPrices(priceUSD, priceDAI, -totalDecDel, false);
        newOracleGetPrices(priceUSD, priceDAI, -totalDecDel, true); // just in case.
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
        newOracleGetPrices(priceUSDT, priceUSDC, totalDecDel, false);
        newOracleGetPrices(priceUSDC, priceUSDT, totalDecDel, true);
    }

    function test_math_sqrt_constraints() public {
        // uint256 price = _getPrice(443637);
        // uint256 price = 1;
        uint160 sqrtPrice = ALMMathLib.getSqrtPriceX96FromPrice(
            340256786833063481322211904572563530436318729319284211712
        );
        console.log(sqrtPrice);
        console.log(ud(9e18).sqrt().unwrap());

        int128 m = ABDKMath64x64.sqrt(int128(9));
        console.log(m);

        console.log(sqrt(9e18));
        console.log(mulDiv(4e18, 5, 2e18));
    }

    function test_decimals_constraints() public {
        int256 tokensDelta = -18;
        int256 feedsDelta = -18;

        uint256 ratio = 10 ** uint256(int256(tokensDelta) + 18); // 1
        uint256 scaleFactor = 10 ** uint256(int256(feedsDelta) + 18); // 1

        uint256 Q = 1e18;
        uint256 B = 1;

        uint256 p1 = mul18(mulDiv(Q, scaleFactor, B), ratio);
        console.log("p1", p1);
        console.log(ALMMathLib.getSqrtPriceX96FromPrice(p1));

        /// -----------

        int256 _totalDecimalsDelta = tokensDelta + feedsDelta;
        vm.expectRevert();
        scaleFactor = 10 ** SafeCast.toUint256(_totalDecimalsDelta + 18);

        newOracleGetPrices(1, 1, 18, false);
    }

    function part_compare_oracle_with_v4_pool(
        AggregatorV3Interface feedBase,
        AggregatorV3Interface feedQuote,
        bool isInvertedPool,
        int256 tokenDecimalsDelta,
        PoolKey memory poolKey
    ) public {
        _compare_oracle_formulas(feedBase, feedQuote, isInvertedPool, tokenDecimalsDelta);
        uint256 poolSQRT = getV4PoolSQRTPrice(poolKey);
        console.log("poolSQRT  ", poolSQRT);
    }

    function part_compare_oracle_with_v3_pool(
        AggregatorV3Interface feedBase,
        AggregatorV3Interface feedQuote,
        bool isInvertedPool,
        int256 tokenDecimalsDelta,
        address pool
    ) public {
        _compare_oracle_formulas(feedBase, feedQuote, isInvertedPool, tokenDecimalsDelta);
        uint256 poolSQRT = getV3PoolSQRTPrice(pool);
        console.log("poolSQRT  ", poolSQRT);
    }

    function _compare_oracle_formulas(
        AggregatorV3Interface feedBase,
        AggregatorV3Interface feedQuote,
        bool isInvertedPool,
        int256 tokenDecimalsDelta
    ) private {
        int256 totalDecDel;
        uint256 priceBase;
        uint256 priceQuote;
        {
            uint256 fDecBase;
            uint256 fDecQuote;
            (fDecBase, priceBase) = getFeedsData(feedBase);
            (fDecQuote, priceQuote) = getFeedsData(feedQuote);
            totalDecDel = int256(fDecQuote) - int256(fDecBase) + tokenDecimalsDelta;
        }

        (uint256 priceO, uint256 sqrtPriceO) = oracleGetPrices(priceBase, priceQuote, totalDecDel, isInvertedPool);
        (uint256 priceN, uint256 sqrtPriceN) = newOracleGetPrices(priceBase, priceQuote, totalDecDel, isInvertedPool);

        console.log("sqrtPriceO", sqrtPriceO);
        console.log("sqrtPriceN", sqrtPriceN);
    }

    // ** Helpers

    function newOracleGetPrices(
        uint256 _priceBase,
        uint256 _priceQuote,
        int256 _totalDecimalsDelta,
        bool _isInvertedPool
    ) public view returns (uint256 _price, uint160 _sqrtPriceX96) {
        if (_totalDecimalsDelta < -18) revert("DecimalsDeltaNotValid");
        uint256 scaleFactor = 10 ** SafeCast.toUint256(_totalDecimalsDelta + 18);
        _price = mulDiv(_priceQuote, scaleFactor, _priceBase);

        if (_totalDecimalsDelta < 0) {
            _priceBase = _priceBase * 10 ** uint256(-_totalDecimalsDelta);
        } else if (_totalDecimalsDelta > 0) {
            _priceQuote = _priceQuote * 10 ** uint256(_totalDecimalsDelta);
        }
        bool invert = _priceBase <= _priceQuote;
        (uint256 lowP, uint256 highP) = invert ? (_priceBase, _priceQuote) : (_priceQuote, _priceBase);
        uint256 r = mulDiv(lowP, type(uint256).max, highP);
        r = sqrt(r);
        if (invert != _isInvertedPool) r = type(uint256).max / r;
        r = r >> 32;
        _sqrtPriceX96 = SafeCast.toUint160(r);
        require(_price != 0, "PriceZero");
        require(_sqrtPriceX96 != 0, "SqrtPriceZero");
    }

    function oracleGetPrices(
        uint256 _priceBase,
        uint256 _priceQuote,
        int256 _totalDecimalsDelta,
        bool _isInvertedPool
    ) public pure returns (uint256 _price, uint160 _sqrtPriceX96) {
        uint256 scaleFactor = 10 ** uint256(_totalDecimalsDelta + 18);
        _price = mulDiv(_priceQuote, scaleFactor, _priceBase);
        uint256 __price = _isInvertedPool ? ALMMathLib.div18(ALMMathLib.WAD, _price) : _price;
        _sqrtPriceX96 = SafeCast.toUint160(ud(__price).sqrt().mul(ud(2 ** 96)).unwrap());
    }
}
