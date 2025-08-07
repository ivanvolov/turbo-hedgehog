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

    /// @dev All tests here should give the same sqrt price per pair but different QUOTE in terms of BASE price.
    function test_strategies_oracles_mainnet() public {
        console.log("\n> ETH_USDC");
        {
            console.log("price ", uint256(288621730488643662729183232)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDC,
                true,
                int8(18 - 6),
                ETH_USDC_key
            );
            console.log("");
            console.log("price ", uint256(3464742582)); // 1e18*(sqrt/q96)**2
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
            console.log("price ", uint256(3465122625)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_WETH,
                true,
                int8(6 - 18),
                MConstants.uniswap_v3_USDC_WETH_POOL
            );
            console.log("");
            console.log("price ", uint256(288590075487514392317132800)); // 1e18*(sqrt/q96)**2
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
            console.log("price ", uint256(288620794971550286434271232)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDT,
                true,
                int8(18 - 6),
                ETH_USDT_key
            );
            console.log("");
            console.log("price ", uint256(3464753813)); // 1e18*(sqrt/q96)**2
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
            console.log("price ", uint256(3457981742)); // 1e18*(sqrt/q96)**2
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDT,
                MConstants.chainlink_feed_WETH,
                false,
                int8(6 - 18),
                MConstants.uniswap_v3_WETH_USDT_POOL
            );
            console.log("");
            console.log("price ", uint256(288620794971550286434271232)); // 1e18/(sqrt/q96)**2
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
            console.log("price ", uint256(999918481968058368)); // 1e18/(sqrt/q96)**2
            console.log("V3 pr ", uint256(999966251147032576)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_USDT,
                true,
                int8(6 - 6),
                USDC_USDT_key
            );
            console.log("V3poolSQRT", getV3PoolSQRTPrice(MConstants.uniswap_v3_USDC_USDT_POOL));
            console.log("");
            console.log("price ", uint256(1000081524677672832)); // 1e18*(sqrt/q96)**2
            console.log("V3 pr ", uint256(1000033749991990912)); // 1e18*(sqrt/q96)**2
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
            console.log("price ", uint256(1141390447233364262912)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_CBBTC,
                true,
                int8(6 - 8),
                MConstants.uniswap_v3_USDC_CBBTC_POOL
            );
            console.log("");
            console.log("price ", uint256(876124381822116)); // 1e18*(sqrt/q96)**2
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
            console.log("price ", uint256(1000017)); // 1e18*(sqrt/q96)**2
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_USDC,
                MConstants.chainlink_feed_DAI,
                false,
                int8(6 - 18),
                MConstants.uniswap_v3_DAI_USDC_POOL
            );
            console.log("");
            console.log("price ", uint256(999982091765034127302141673472)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v3_pool(
                MConstants.chainlink_feed_DAI,
                MConstants.chainlink_feed_USDC,
                true,
                int8(18 - 6),
                MConstants.uniswap_v3_DAI_USDC_POOL
            );
        }
    }

    /// @dev All tests here should give the same sqrt price per pair but different QUOTE in terms of BASE price.
    function test_strategies_oracles_unichain() public {
        _select_unichain_fork(23567130);
        console.log("\n> ETH_WSTETH with one feed");
        {
            mock_latestRoundData(UConstants.chronicle_feed_WSTETH, 1210060639502791600);
            console.log("price ", uint256(1206863694718699008)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                UConstants.zero_feed,
                UConstants.chronicle_feed_WSTETH,
                true,
                int8(18),
                ETH_WSTETH_key_unichain
            );
            console.log("price ", uint256(828593986525615360)); // 1e18*(sqrt*q96)**2
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
            console.log("price ", uint256(3641724659)); // 1e18*(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_USDC,
                UConstants.chronicle_feed_WETH,
                false,
                int8(6 - 18),
                ETH_USDC_key_unichain
            );
            console.log("price ", uint256(274595169448541420955631616)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_WETH,
                UConstants.chronicle_feed_USDC,
                true,
                int8(18 - 6),
                ETH_USDC_key_unichain
            );
        }

        _select_unichain_fork(23128176);
        console.log("\n> ETH_USDT");
        {
            mock_latestRoundData(UConstants.chronicle_feed_WETH, 3754570000000000000000);
            mock_latestRoundData(UConstants.chronicle_feed_USDT, 999983595619733749);
            console.log("price ", uint256(3747240658)); // 1e18*(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_USDT,
                UConstants.chronicle_feed_WETH,
                false,
                int8(6 - 18),
                ETH_USDT_key_unichain
            );
            console.log("price ", uint256(266863031031690038026960896)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_WETH,
                UConstants.chronicle_feed_USDT,
                true,
                int8(18 - 6),
                ETH_USDT_key_unichain
            );
        }

        _select_unichain_fork(23404999);
        console.log("\n> USDC_USDT");
        {
            mock_latestRoundData(UConstants.chronicle_feed_USDT, 999620000000000000);
            mock_latestRoundData(UConstants.chronicle_feed_USDC, 999735368664584522);
            console.log("price ", uint256(999767279958814080)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_USDC,
                UConstants.chronicle_feed_USDT,
                true,
                int8(0),
                USDC_USDT_key_unichain
            );
            console.log("price ", uint256(1000232774212410240)); // 1e18*(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                UConstants.chronicle_feed_USDT,
                UConstants.chronicle_feed_USDC,
                false,
                int8(0),
                USDC_USDT_key_unichain
            );
        }
    }

    /// @dev All tests here should give the same sqrt price per pair but different QUOTE in terms of BASE price.
    function test_strategies_oracles_base() public {
        _select_base_fork(33774814);
        console.log("\n> USDC_CBBTC");
        {
            console.log("price ", uint256(1147355937836650594304)); // 1e18/(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                BConstants.chainlink_feed_USDC,
                BConstants.chainlink_feed_CBBTC,
                true,
                int8(6 - 8),
                USDC_CBBTC_key_base
            );
            console.log("price ", uint256(871569115583703)); // 1e18*(sqrt/q96)**2
            part_compare_oracle_with_v4_pool(
                BConstants.chainlink_feed_CBBTC,
                BConstants.chainlink_feed_USDC,
                false,
                int8(8 - 6),
                USDC_CBBTC_key_base
            );
        }
    }

    /// @dev All tests here should give the same sqrt price per pair but different QUOTE in terms of BASE price.
    function test_other_possible_oracles() public {
        _select_mainnet_fork(23075773);
        console.log("\n> WSTETH_WETH with one feed");
        {
            // Warning: WSTETH_WETH only exist on V3 mainnet, but WSTETH/WETH feed exist only on Unichain. This test does not make much sense.
            mock_latestRoundData(UConstants.chronicle_feed_WSTETH, 1210148407573673000);
            console.log("price ", uint256(827508413011596672)); // 1e18/(sqrt/q96)**2.
            part_compare_oracle_with_v3_pool(
                UConstants.chronicle_feed_WSTETH, // Yes, this is a wrong network contract address byt we mock it, should be fine.
                MConstants.zero_feed,
                true,
                int256(-18),
                MConstants.uniswap_v3_WSTETH_WETH_POOL
            );
            console.log("price ", uint256(1208446928485772288)); // 1e18*(sqrt/q96)**2.
            part_compare_oracle_with_v3_pool(
                MConstants.zero_feed,
                UConstants.chronicle_feed_WSTETH,
                false,
                int256(18),
                MConstants.uniswap_v3_WSTETH_WETH_POOL
            );
        }

        _select_base_fork(33774814);
        // This is experimental, even don't have sqrt price to compare too, so look into price.
        console.log("\n> WSTETH=>USD");
        {
            console.log(" WETH/USD feed price:", getFeedPrice(BConstants.chainlink_feed_WETH));
            print_oracle_answer(BConstants.chainlink_feed_WETH, BConstants.chainlink_feed_WSTETH, false, int8(10));
            print_oracle_answer(BConstants.chainlink_feed_WETH, BConstants.chainlink_feed_WSTETH, true, int8(10));
            print_oracle_answer(BConstants.chainlink_feed_WSTETH, BConstants.chainlink_feed_WETH, false, int8(-10));
            print_oracle_answer(BConstants.chainlink_feed_WSTETH, BConstants.chainlink_feed_WETH, true, int8(-10));
        }
    }

    // ** Constraints

    //TODO: Retest this constraints in sim. ALMMathLib.getSqrtPriceX96FromPrice(340256786833063481322211904572563530436318729319284211712);
    //TODO: Think about scaleFactor constraints, do wee need them? No we don't.
    function test_constraints() public {
        TestLib.newOracleGetPrices(1e18, 1e18, int256(-18), false);
    }

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
        IOracle mock_oracle = _create_oracle(feedB, feedQ, 24 hours, 24 hours, isInvertedPool, int8(tokenDecDel));
        (uint256 priceN, uint256 sqrtPriceN) = mock_oracle.poolPrice();
        console.log("priceO", priceO);
        console.log("priceN", priceN);

        console.log("sqrtPriceO", sqrtPriceO);
        console.log("sqrtPriceN", sqrtPriceN);
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
