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

contract OracleTest is ALMTestBase {
    using SafeERC20 for IERC20;

    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(22375550);
        _create_accounts();
    }

    // ** Notice
    // 1. _isInvertedAssets is everywhere the assets operations are, so we deposit in Base or Quote, withdraw from Long or Short. Rebalance to Base o Quote
    // 2. _isInvertedPool, expect pools to be Quote:Base, and invert assets if it's true. So everywhere there currencies are used together with token we need these variable.
    function test_oracle_pool_price_USDC_WETH() public {
        _test_currencies_order(MConstants.USDC, MConstants.WETH); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_USDC, // Base
            MConstants.chainlink_feed_WETH, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_WETH_USDC_POOL, // pool always returns in it's own order
            true, // false if QUOTE : BASE
            int8(6 - 18) // BDec - QDec
        );
    }

    /// @dev Was uncovered.
    function test_oracle_pool_price_USDC_WETH_R() public {
        _test_currencies_order(MConstants.USDC, MConstants.WETH); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_WETH, // Base
            MConstants.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_WETH_USDC_POOL, // pool always returns in it's own order
            false, // false if QUOTE : BASE
            int8(18 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_WETH_USDT() public {
        _test_currencies_order(MConstants.WETH, MConstants.USDT); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_USDT, // Base
            MConstants.chainlink_feed_WETH, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_WETH_USDT_POOL,
            false, // false if QUOTE : BASE
            int8(6 - 18) // BDec - QDec
        );
    }

    /// @dev Was uncovered.
    function test_oracle_pool_price_WETH_USDT_R() public {
        _test_currencies_order(MConstants.WETH, MConstants.USDT); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_WETH, // Base
            MConstants.chainlink_feed_USDT, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_WETH_USDT_POOL,
            true, // false if QUOTE : BASE
            int8(18 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_USDC_USDT() public {
        _test_currencies_order(MConstants.USDC, MConstants.USDT); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_USDT, // Base
            MConstants.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_USDC_USDT_POOL,
            false, // false if QUOTE : BASE
            int8(6 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_USDC_USDT_R() public {
        _test_currencies_order(MConstants.USDC, MConstants.USDT); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_USDC, // Base
            MConstants.chainlink_feed_USDT, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_USDC_USDT_POOL,
            true, // false if QUOTE : BASE
            int8(6 - 6) // BDec - QDec
        );
    }

    /// @dev Was uncovered.
    function test_oracle_pool_price_DAI_USDC() public {
        _test_currencies_order(MConstants.DAI, MConstants.USDC); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_DAI, // Base
            MConstants.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_DAI_USDC_POOL,
            true, // false if QUOTE : BASE
            int8(18 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_DAI_USDC_R() public {
        _test_currencies_order(MConstants.DAI, MConstants.USDC); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_USDC, // Base
            MConstants.chainlink_feed_DAI, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_DAI_USDC_POOL,
            false, // false if QUOTE : BASE
            int8(6 - 18) // BDec - QDec
        );
    }

    /// @dev Was uncovered.
    function test_oracle_pool_price_USDC_cbBTC() public {
        _test_currencies_order(MConstants.USDC, MConstants.cbBTC); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_cbBTC, // Base
            MConstants.chainlink_feed_USDC, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_cbBTC_USDC_POOL,
            false, // false if QUOTE : BASE
            int8(8 - 6) // BDec - QDec
        );
    }

    function test_oracle_pool_price_USDC_cbBTC_R() public {
        _test_currencies_order(MConstants.USDC, MConstants.cbBTC); // quote, base
        part_test_oracle_pool_price(
            MConstants.chainlink_feed_USDC, // Base
            MConstants.chainlink_feed_cbBTC, // Quote, oracle always return Quote in BASE
            MConstants.uniswap_v3_cbBTC_USDC_POOL,
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

    function test_strategy_oracles_chainlink() public {
        IOracle mock_oracle;

        console.log("> DN/ETHALM");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDC,
                10 hours,
                10 hours,
                true,
                int8(6 - 18)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            // Human readable oraclePrice: 1817030479873254341041
            assertEq(price, 1817030479);
            assertEq(poolPrice, 550348500785935357994619527);
        }

        console.log("> ETH-R-ALM/ETH-R2-ALM");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDT,
                1 hours,
                10 hours,
                false,
                int8(6 - 18)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            // Human readable oraclePrice: 1816422855463561861669
            assertEq(price, 1816422855);
            assertEq(poolPrice, 1816422855);
        }

        console.log("> BTCALMTest");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_cbBTC,
                MConstants.chainlink_feed_USDC,
                10 hours,
                10 hours,
                true,
                int8(6 - 8)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            // Human readable oraclePrice: 95041476087981443534362
            assertEq(price, 950414760879814435343);
            assertEq(poolPrice, 1052172210661252);
        }

        // This example is not present in strategies
        {
            // mock_oracle = _create_oracle(MConstants.chainlink_feed_USDC, MConstants.chainlink_feed_cbBTC, 50 hours, 50 hours);
            // console.log("oracle", mock_oracle.price());
        }

        console.log("> UNICORD-R");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_DAI,
                MConstants.chainlink_feed_USDC,
                10 hours,
                10 hours,
                true,
                int8(0)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 1000217771097615134);
            assertEq(poolPrice, 999782276316310439);
        }

        console.log("> UNICORD");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_USDT,
                MConstants.chainlink_feed_USDC,
                10 hours,
                10 hours,
                true,
                int8(0)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 1000334517046988714);
            assertEq(poolPrice, 999665594817245518);
        }
    }

    /// Api3 Market only offers a 24-hour heartbeat interval.
    /// It is important to buy price feeds yourself because deviation thresholds can be updated - we have a vulnerability here.
    /// See plans and durations for more update functionality: https://docs.api3.org/dapps/integration/#plan-durations.
    /// Look into gas grants, they can purchase plans for you: https://docs.api3.org/dapps/integration/#gas-grants.
    function test_strategy_oracles_api3() public {
        IOracle mock_oracle;
        vm.rollFork(22974236);

        console.log("> DN/ETHALM");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473), // WETH
                AggregatorV3Interface(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f), // USDC
                24 hours,
                24 hours,
                true,
                int8(6 - 18)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 3635798239);
            assertEq(poolPrice, 275042764824882792402936746);
        }

        console.log("> ETH-R-ALM/ETH-R2-ALM");
        {
            select_arbitrum_fork(360360800);
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473), // WETH
                AggregatorV3Interface(0x4eadC6ee74b7Ceb09A4ad90a33eA2915fbefcf76), // USDT
                24 hours,
                24 hours,
                false,
                int8(6 - 18)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 3683777823);
            assertEq(poolPrice, 3683777823);
        }

        console.log("> BTCALMTest");
        {
            select_sepolia_fork(8817967);
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0xa4183Cbf2eE868dDFccd325531C4f53F737FFF68), // cbBTC
                AggregatorV3Interface(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f), // USDC
                24 hours,
                24 hours,
                true,
                int8(6 - 8)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 1193629881221990642759);
            assertEq(poolPrice, 837780635129743);
        }

        // This example is not present in strategies
        {
            // mock_oracle = _create_oracle(MConstants.chainlink_feed_USDC, MConstants.chainlink_feed_cbBTC, 24 hours, 24 hours);
            // console.log("oracle", mock_oracle.price());
        }

        console.log("> UNICORD-R");
        {
            select_sepolia_fork(8818009);
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x85b6dD270538325A9E0140bd6052Da4ecc18A85c), //DAI
                AggregatorV3Interface(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f), // USDC
                24 hours,
                24 hours,
                true,
                int8(0)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 1000207563825876356);
            assertEq(poolPrice, 999792479247924893);
        }

        console.log("> UNICORD");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x4eadC6ee74b7Ceb09A4ad90a33eA2915fbefcf76), // USDT
                AggregatorV3Interface(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f), // USDC
                24 hours,
                24 hours,
                true,
                int8(0)
            );

            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 1000849189697260507);
            assertEq(poolPrice, 999151530814030661);
        }
    }

    function test_strategy_oracles_chronicle() public {
        IOracle mock_oracle;
        select_sepolia_fork(8818766);

        console.log("> DN/ETHALM");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x3b8Cd6127a6CBEB9336667A3FfCD32B3509Cb5D9), // WETH
                AggregatorV3Interface(0xb34d784dc8E7cD240Fe1F318e282dFdD13C389AC), // USDC
                24 hours,
                24 hours,
                true,
                int8(6 - 18)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 3646184618);
            assertEq(poolPrice, 274259288754423679596577136);
        }

        console.log("> ETH-R-ALM/ETH-R2-ALM");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x3b8Cd6127a6CBEB9336667A3FfCD32B3509Cb5D9), // WETH
                AggregatorV3Interface(0x8c852EEC6ae356FeDf5d7b824E254f7d94Ac6824), // USDT
                24 hours,
                24 hours,
                false,
                int8(6 - 18)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 3644507977);
            assertEq(poolPrice, 3644507977);
        }

        console.log("> BTCALMTest");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0xe4f05C62c09a3ec000a3f3895eFD2Ec9a1A11742), // cbBTC
                AggregatorV3Interface(0xb34d784dc8E7cD240Fe1F318e282dFdD13C389AC), // USDC
                24 hours,
                24 hours,
                true,
                int8(6 - 8)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 1190799525762077236252);
            assertEq(poolPrice, 839771916570111);
        }

        // This example is not present in strategies
        {
            // mock_oracle = _create_oracle(MConstants.chainlink_feed_USDC, MConstants.chainlink_feed_cbBTC, 24 hours, 24 hours);
            // console.log("oracle", mock_oracle.price());
        }

        console.log("> UNICORD-R");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0xaf900d10f197762794C41dac395C5b8112eD13E1), //DAI
                AggregatorV3Interface(0xb34d784dc8E7cD240Fe1F318e282dFdD13C389AC), // USDC
                24 hours,
                24 hours,
                true,
                int8(0)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 999979154161890803);
            assertEq(poolPrice, 1000020846272667222);
        }

        console.log("> UNICORD");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x8c852EEC6ae356FeDf5d7b824E254f7d94Ac6824), // USDT
                AggregatorV3Interface(0xb34d784dc8E7cD240Fe1F318e282dFdD13C389AC), // USDC
                24 hours,
                24 hours,
                true,
                int8(0)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, uint256 poolPrice) = mock_oracle.poolPrice();
            assertEq(price, 1000460046004600460);
            assertEq(poolPrice, 999540165540405454);
        }
    }

    function test_oracle_constraints() public {
        // Normal oracle price
        {
            uint256 priceQuote = 1816937883999999885312;
            uint256 decimalsQuote = 18;
            uint256 priceBase = 99994904;
            uint256 decimalsBase = 8;
            console.log("price", mock_calc_price(priceQuote, decimalsQuote, priceBase, decimalsBase));
        }

        // This is illustration of overflow if decimalsBase - decimalsQuote < -18
        {
            uint256 decimals_to_overflow = 10;
            uint256 priceQuote = 1816937883999999885312 * (10 ** decimals_to_overflow);
            uint256 decimalsQuote = 18 + decimals_to_overflow;
            uint256 priceBase = 99994904;
            uint256 decimalsBase = 8;
            try this.mock_calc_price(priceQuote, decimalsQuote, priceBase, decimalsBase) {
                revert("This should revert");
            } catch {}
        }

        // No overflow if decimalsBase - decimalsQuote > 18
        {
            uint256 priceQuote = 1816000000;
            uint256 decimalsQuote = 6;
            uint256 priceBase = 99994904000000005278531584;
            uint256 decimalsBase = 26;
            console.log("price", mock_calc_price(priceQuote, decimalsQuote, priceBase, decimalsBase));
        }
    }

    // ** Helpers

    function mock_calc_price(
        uint256 priceQuote,
        uint256 decimalsQuote,
        uint256 priceBase,
        uint256 decimalsBase
    ) public returns (uint256 price) {
        IOracle mock_oracle = _create_oracle(
            MConstants.chainlink_feed_WETH,
            MConstants.chainlink_feed_USDC,
            10 hours,
            10 hours,
            true,
            int8(int256(decimalsBase) - int256(decimalsQuote))
        );

        vm.mockCall(
            address(MConstants.chainlink_feed_WETH),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(priceQuote), uint256(0), uint256(block.timestamp), uint80(0))
        );
        vm.mockCall(
            address(MConstants.chainlink_feed_USDC),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(priceBase), uint256(0), uint256(block.timestamp), uint80(0))
        );
        (price, ) = mock_oracle.poolPrice();
    }

    function select_arbitrum_fork(uint256 block_number) internal {
        uint256 fork = vm.createFork(ARBITRUM_RPC_URL);
        vm.selectFork(fork);
        vm.rollFork(block_number);
        _create_accounts();
    }

    function select_sepolia_fork(uint256 block_number) internal {
        uint256 fork = vm.createFork(SEPOLIA_RPC_URL);
        vm.selectFork(fork);
        vm.rollFork(block_number);
        _create_accounts();
    }

    function whitelist_chronicle_feed(address feed, IOracle _oracle) internal {
        vm.prank(deployer.addr);
        IChronicleSelfKisser(0x9eE458DefDc50409DbF153515DA54Ff5B744e533).selfKiss(feed, address(_oracle));
    }
}
