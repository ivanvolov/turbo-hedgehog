// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PRBMath} from "@prb-math/PRBMath.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";

contract OracleTest is ALMTestBase {
    using SafeERC20 for IERC20;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(22375550);
    }

    // ** Notice
    // 1. _isInvertedAssets is everywhere the assets operations are, so we deposit in Base or Quote, withdraw from Long or Short. Rebalance to Base o Quote
    // 2. _isInvertedPool, expect pools to be Quote:Base, and invert assets if it's true. So everywhere there currencies are used together with token we need these variable.
    function test_oracle_pool_price_USDC_WETH() public {
        __test_currencies_order(TestLib.USDC, TestLib.WETH); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_USDC, // Base
            TestLib.chainlink_feed_WETH, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_WETH_USDC_POOL, // pool always returns in it's own order
            true, // false if QUOTE : BASE
            int8(6 - 18) // BDec - QDec
        );
    }

    //!/ @dev was uncovered
    function test_oracle_pool_price_USDC_WETH_R() public {
        __test_currencies_order(TestLib.USDC, TestLib.WETH); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_WETH, // Base
            TestLib.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_WETH_USDC_POOL, // pool always returns in it's own order
            false, // false if QUOTE : BASE
            int8(18 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_WETH_USDT() public {
        __test_currencies_order(TestLib.WETH, TestLib.USDT); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_USDT, // Base
            TestLib.chainlink_feed_WETH, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_WETH_USDT_POOL,
            false, // false if QUOTE : BASE
            int8(6 - 18) // BDec - QDec
        );
    }

    //!/ @dev was uncovered
    function test_oracle_pool_price_WETH_USDT_R() public {
        __test_currencies_order(TestLib.WETH, TestLib.USDT); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_WETH, // Base
            TestLib.chainlink_feed_USDT, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_WETH_USDT_POOL,
            true, // false if QUOTE : BASE
            int8(18 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_USDC_USDT() public {
        __test_currencies_order(TestLib.USDC, TestLib.USDT); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_USDT, // Base
            TestLib.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_USDC_USDT_POOL,
            false, // false if QUOTE : BASE
            int8(6 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_USDC_USDT_R() public {
        __test_currencies_order(TestLib.USDC, TestLib.USDT); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_USDC, // Base
            TestLib.chainlink_feed_USDT, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_USDC_USDT_POOL,
            true, // false if QUOTE : BASE
            int8(6 - 6) // BDec - QDec
        );
    }

    //!/ @dev was uncovered
    function test_oracle_pool_price_DAI_USDC() public {
        __test_currencies_order(TestLib.DAI, TestLib.USDC); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_DAI, // Base
            TestLib.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_DAI_USDC_POOL,
            true, // false if QUOTE : BASE
            int8(18 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_DAI_USDC_R() public {
        __test_currencies_order(TestLib.DAI, TestLib.USDC); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_USDC, // Base
            TestLib.chainlink_feed_DAI, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_DAI_USDC_POOL,
            false, // false if QUOTE : BASE
            int8(6 - 18) // BDec - QDec
        );
    }

    //!/ @dev was uncovered
    function test_oracle_pool_price_USDC_cbBTC() public {
        __test_currencies_order(TestLib.USDC, TestLib.cbBTC); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_cbBTC, // Base
            TestLib.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_cbBTC_USDC_POOL,
            false, // false if QUOTE : BASE
            int8(8 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_USDC_cbBTC_R() public {
        __test_currencies_order(TestLib.USDC, TestLib.cbBTC); // quote, base
        part_test_oracle_pool_price(
            TestLib.chainlink_feed_USDC, // Base
            TestLib.chainlink_feed_cbBTC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_cbBTC_USDC_POOL,
            true, // false if QUOTE : BASE
            int8(6 - 8) // BDec - QDec
        );
    }

    function part_test_oracle_pool_price(
        AggregatorV3Interface feedB,
        AggregatorV3Interface feedQ,
        address pool,
        bool isInverted,
        int8 decimalsDelta
    ) internal {
        IOracle mockOracle = _create_oracle(feedQ, feedB, 50 hours, 50 hours, isInverted, decimalsDelta);

        uint160 sqrtPriceX96 = getV3PoolSQRTPrice(pool);
        uint256 poolPrice = TestLib.getPriceFromSqrtPriceX96(sqrtPriceX96);

        uint256 __price = mockOracle.price();
        (uint256 _price, uint256 _poolPrice) = mockOracle.poolPrice();
        assertEq(_price, __price);

        console.log("calc price    ", _price);
        console.log("(.)  poolPrice", poolPrice);
        console.log("calc poolPrice", _poolPrice);
    }

    function test_strategy_oracles() public {
        IOracle oracle1 = _create_oracle(
            TestLib.chainlink_feed_WETH,
            TestLib.chainlink_feed_USDC,
            10 hours,
            10 hours,
            true,
            int8(6 - 18)
        );
        (uint256 price, uint256 poolPrice) = oracle1.poolPrice();
        console.log("> DN/ETHALM");
        assertEq(price, 1817030479873254341041);
        assertEq(poolPrice, 550348500483051885843984301);

        IOracle oracle2 = _create_oracle(
            TestLib.chainlink_feed_WETH,
            TestLib.chainlink_feed_USDT,
            1 hours,
            10 hours,
            false,
            int8(6 - 18)
        );
        (uint256 price2, uint256 poolPrice2) = oracle2.poolPrice();
        console.log("> ETH-R-ALM/ETH-R2-ALM");
        assertEq(price2, 1816422855463561861669);
        assertEq(poolPrice2, 1816422855);

        IOracle oracle3 = _create_oracle(
            TestLib.chainlink_feed_cbBTC,
            TestLib.chainlink_feed_USDC,
            10 hours,
            10 hours,
            true,
            int8(6 - 8)
        );
        (uint256 price3, uint256 poolPrice3) = oracle3.poolPrice();
        console.log("> BTCALMTest");
        assertEq(price3, 95041476087981443534362);
        assertEq(poolPrice3, 1052172210661252);

        // IOracle oracle4 = _create_oracle(TestLib.chainlink_feed_USDC, TestLib.chainlink_feed_cbBTC, 50 hours, 50 hours);
        // console.log("oracle", oracle4.price());

        IOracle oracle5 = _create_oracle(
            TestLib.chainlink_feed_DAI,
            TestLib.chainlink_feed_USDC,
            10 hours,
            10 hours,
            true,
            int8(0)
        );
        (uint256 price5, uint256 poolPrice5) = oracle5.poolPrice();
        console.log("> UNICORD-R");
        assertEq(price5, 1000217771097615134);
        assertEq(poolPrice5, 999782276316310439);

        IOracle oracle6 = _create_oracle(
            TestLib.chainlink_feed_USDT,
            TestLib.chainlink_feed_USDC,
            10 hours,
            10 hours,
            true,
            int8(0)
        );
        (uint256 price6, uint256 poolPrice6) = oracle6.poolPrice();
        console.log("> UNICORD");
        assertEq(price6, 1000334517046988714);
        assertEq(poolPrice6, 999665594817245518);
    }

    // ** Helpers

    function test_oracle_constraints() public {
        /// @dev: normal oracle price
        {
            uint256 priceQuote = 1816937883999999885312;
            uint256 decimalsQuote = 18;
            uint256 priceBase = 99994904;
            uint256 decimalsBase = 8;
            console.log("price", mock_calc_price(priceQuote, decimalsQuote, priceBase, decimalsBase));
        }

        /// @dev: this is illustration of overflow if decimalsBase - decimalsQuote < -18
        {
            uint256 decimals_to_overflow = 10;
            uint256 priceQuote = 1816937883999999885312 * (10 ** decimals_to_overflow);
            uint256 decimalsQuote = 18 + decimals_to_overflow;
            uint256 priceBase = 99994904;
            uint256 decimalsBase = 8;
            vm.expectRevert();
            console.log("price", mock_calc_price(priceQuote, decimalsQuote, priceBase, decimalsBase));
        }

        /// @dev: no overflow if decimalsBase - decimalsQuote > 18
        {
            uint256 priceQuote = 1816000000;
            uint256 decimalsQuote = 6;
            uint256 priceBase = 99994904000000005278531584;
            uint256 decimalsBase = 26;
            console.log("price", mock_calc_price(priceQuote, decimalsQuote, priceBase, decimalsBase));
        }
    }

    function mock_calc_price(
        uint256 priceQuote,
        uint256 decimalsQuote,
        uint256 priceBase,
        uint256 decimalsBase
    ) internal pure returns (uint256) {
        uint256 scaleFactor = 18 + decimalsBase - decimalsQuote;
        return PRBMath.mulDiv(uint256(priceQuote), 10 ** scaleFactor, uint256(priceBase));
    }

    function __test_currencies_order(address token0, address token1) internal pure {
        if (token0 >= token1) revert("Out of order");
    }
}
