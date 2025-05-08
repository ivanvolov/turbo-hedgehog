// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PRBMath} from "@prb-math/PRBMath.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";

contract ConfigurationsTest is ALMTestBase {
    using SafeERC20 for IERC20;
    using TokenWrapperLib for uint256;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(22375550);
    }

    // ** Notice
    // 1. _isInvertedAssets is everywhere the assets operations are, so we deposit in Base ot Quote, withdraw from Long or Short. Rebalance to Base o Quote
    // 2. _isInvertedPool, expect pools to be Quote:Base, and invert assets if it's true. So everywhere there currencies are used together with token we need these variable.
    function test_decimals_USDC_WETH() public {
        __test_currencies_order(TestLib.USDC, TestLib.WETH); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_USDC, // Base
            TestLib.chainlink_feed_WETH, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_WETH_USDC_POOL, // pool always returns in it's own order
            true, // false if QUOTE : BASE
            int8(6 - 18), // BDec - QDec
            1
        );
    }

    // ! was uncovered
    function test_decimals_USDC_WETH_R() public {
        __test_currencies_order(TestLib.USDC, TestLib.WETH); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_WETH, // Base
            TestLib.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_WETH_USDC_POOL, // pool always returns in it's own order
            false, // false if QUOTE : BASE
            int8(18 - 6), // BDec - QDec
            1
        );
    }

    function test_decimals_WETH_USDT() public {
        __test_currencies_order(TestLib.WETH, TestLib.USDT); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_USDT, // Base
            TestLib.chainlink_feed_WETH, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_WETH_USDT_POOL,
            false, // false if QUOTE : BASE
            int8(6 - 18), // BDec - QDec
            1
        );
    }

    //! was uncovered
    function test_decimals_WETH_USDT_R() public {
        __test_currencies_order(TestLib.WETH, TestLib.USDT); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_WETH, // Base
            TestLib.chainlink_feed_USDT, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_WETH_USDT_POOL,
            true, // false if QUOTE : BASE
            int8(18 - 6), // BDec - QDec
            1
        );
    }

    function test_decimals_USDC_USDT() public {
        __test_currencies_order(TestLib.USDC, TestLib.USDT); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_USDT, // Base
            TestLib.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_USDC_USDT_POOL,
            false, // false if QUOTE : BASE
            int8(6 - 6), // BDec - QDec
            1
        );
    }

    function test_decimals_USDC_USDT_R() public {
        __test_currencies_order(TestLib.USDC, TestLib.USDT); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_USDC, // Base
            TestLib.chainlink_feed_USDT, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_USDC_USDT_POOL,
            true, // false if QUOTE : BASE
            int8(6 - 6), // BDec - QDec
            1
        );
    }

    //! was uncovered
    function test_decimals_DAI_USDC() public {
        __test_currencies_order(TestLib.DAI, TestLib.USDC); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_DAI, // Base
            TestLib.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_DAI_USDC_POOL,
            true, // false if QUOTE : BASE
            int8(18 - 6), // BDec - QDec
            1
        );
    }

    function test_decimals_DAI_USDC_R() public {
        __test_currencies_order(TestLib.DAI, TestLib.USDC); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_USDC, // Base
            TestLib.chainlink_feed_DAI, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_DAI_USDC_POOL,
            false, // false if QUOTE : BASE
            int8(6 - 18), // BDec - QDec
            1
        );
    }

    // ! was uncovered
    function test_decimals_USDC_cbBTC() public {
        __test_currencies_order(TestLib.USDC, TestLib.cbBTC); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_cbBTC, // Base
            TestLib.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_cbBTC_USDC_POOL,
            false, // false if QUOTE : BASE
            int8(8 - 6), // BDec - QDec
            1
        );
    }

    function test_decimals_USDC_cbBTC_R() public {
        __test_currencies_order(TestLib.USDC, TestLib.cbBTC); // quote, base
        part_test_decimals(
            TestLib.chainlink_feed_USDC, // Base
            TestLib.chainlink_feed_cbBTC, // Quote, oracle always return Quote in BASE
            TestLib.uniswap_v3_cbBTC_USDC_POOL,
            true, // false if QUOTE : BASE
            int8(6 - 8), // BDec - QDec
            1
        );
    }

    function part_test_decimals(
        AggregatorV3Interface feedB,
        AggregatorV3Interface feedQ,
        address pool,
        bool isInverted,
        int8 expShift,
        uint256 divider
    ) internal {
        uint160 sqrtPriceX96 = getV3PoolSQRTPrice(pool);

        // console.log("pool_price", ALMMathLib.getPriceFromSqrtPriceX96(sqrtPriceX96));
        // console.log("isInverted", isInverted);
        // console.log("expShift", expShift);

        IOracle oracle1 = create_oracle(feedQ, feedB, 50 hours, 50 hours);
        uint256 oraclePrice = oracle1.price();
        uint256 price = ALMMathLib.getOraclePriceFromPoolPrice(
            ALMMathLib.getPriceFromSqrtPriceX96(sqrtPriceX96),
            isInverted,
            expShift
        );
        console.log("(.) oracle", oraclePrice / divider);
        console.log("price     ", price / divider);

        // uint256 poolPrice = ALMMathLib.getPoolPriceFromOraclePrice(oraclePrice, isInverted, expShift);
        // console.log("pool_price", poolPrice);

        console.log("(.) sqrtPrice", sqrtPriceX96);
        uint160 sqrt = ALMMathLib.getSqrtPriceAtTick(
            ALMMathLib.getTickFromPrice(ALMMathLib.getPoolPriceFromOraclePrice(oraclePrice, isInverted, expShift))
        );
        console.log("sqrt         ", sqrt);
    }

    function test_oracles() public {
        IOracle oracle1 = create_oracle(TestLib.chainlink_feed_WETH, TestLib.chainlink_feed_USDC, 50 hours, 50 hours);
        console.log("oracle", oracle1.price());

        IOracle oracle2 = create_oracle(TestLib.chainlink_feed_USDC, TestLib.chainlink_feed_WETH, 50 hours, 50 hours);
        console.log("oracle", oracle2.price());

        IOracle oracle3 = create_oracle(TestLib.chainlink_feed_cbBTC, TestLib.chainlink_feed_USDC, 50 hours, 50 hours);
        console.log("oracle", oracle3.price());

        IOracle oracle4 = create_oracle(TestLib.chainlink_feed_USDC, TestLib.chainlink_feed_cbBTC, 50 hours, 50 hours);
        console.log("oracle", oracle4.price());

        IOracle oracle5 = create_oracle(TestLib.chainlink_feed_USDC, TestLib.chainlink_feed_USDT, 50 hours, 50 hours);
        console.log("oracle", oracle5.price());

        IOracle oracle6 = create_oracle(TestLib.chainlink_feed_USDT, TestLib.chainlink_feed_USDC, 50 hours, 50 hours);
        console.log("oracle", oracle6.price());

        {
            uint256 priceQuote = 1816937883999999885312;
            uint256 decimalsQuote = 18;
            uint256 priceBase = 99994904;
            uint256 decimalsBase = 8;
            console.log("price", mock_calc_price(priceQuote, decimalsQuote, priceBase, decimalsBase));
        }

        {
            /// @dev: this is illustration of overflow
            // uint256 priceQuote = 1816937883999999885312 * 1e10;
            // uint256 decimalsQuote = 28;
            // uint256 priceBase = 99994904;
            // uint256 decimalsBase = 8;
            // console.log("price", mock_calc_price(priceQuote, decimalsQuote, priceBase, decimalsBase));
        }

        /// @dev: so delta is an oracle problem but only one way oracle problem
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
