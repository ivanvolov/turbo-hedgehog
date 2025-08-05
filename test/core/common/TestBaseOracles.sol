// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** V4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// ** contracts
import {TestBaseShortcuts} from "./TestBaseShortcuts.sol";
import {Oracle} from "@src/core/oracles/Oracle.sol";

// ** libraries
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {Constants as BConstants} from "@test/libraries/constants/BaseConstants.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IOracleTest} from "@test/interfaces/IOracleTest.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AggregatorV3Interface as IAggV3} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

abstract contract TestBaseOracles is TestBaseShortcuts {
    using PoolIdLibrary for PoolKey;

    PoolKey public ETH_USDC_key;
    PoolKey public ETH_USDT_key;
    PoolKey public USDC_USDT_key;
    PoolKey public ETH_WSTETH_key_unichain;
    PoolKey public ETH_USDC_key_unichain;
    PoolKey public ETH_USDT_key_unichain;
    PoolKey public USDC_USDT_key_unichain;
    PoolKey public USDC_CBBTC_key_base;

    constructor() {
        // ** Mainnet

        ETH_USDC_key = _getAndCheckPoolKey(
            ETH,
            IERC20(MConstants.USDC),
            500,
            10,
            0x21c67e77068de97969ba93d4aab21826d33ca12bb9f565d8496e8fda8a82ca27
        );

        ETH_USDT_key = _getAndCheckPoolKey(
            ETH,
            IERC20(MConstants.USDT),
            500,
            10,
            0x72331fcb696b0151904c03584b66dc8365bc63f8a144d89a773384e3a579ca73
        );

        USDC_USDT_key = _getAndCheckPoolKey(
            IERC20(MConstants.USDC),
            IERC20(MConstants.USDT),
            100,
            1,
            0xe018f09af38956affdfeab72c2cefbcd4e6fee44d09df7525ec9dba3e51356a5
        );

        // ** Unichain

        ETH_WSTETH_key_unichain = _getAndCheckPoolKey(
            ETH,
            IERC20(UConstants.WSTETH),
            100,
            1,
            0xd10d359f50ba8d1e0b6c30974a65bf06895fba4bf2b692b2c75d987d3b6b863d
        );

        ETH_USDC_key_unichain = _getAndCheckPoolKey(
            ETH,
            IERC20(UConstants.USDC),
            500,
            10,
            0x3258f413c7a88cda2fa8709a589d221a80f6574f63df5a5b6774485d8acc39d9
        );

        ETH_USDT_key_unichain = _getAndCheckPoolKey(
            ETH,
            IERC20(UConstants.USDT),
            500,
            10,
            0x04b7dd024db64cfbe325191c818266e4776918cd9eaf021c26949a859e654b16
        );

        USDC_USDT_key_unichain = _getAndCheckPoolKey(
            IERC20(UConstants.USDC),
            IERC20(UConstants.USDT),
            100,
            1,
            0x77ea9d2be50eb3e82b62db928a1bcc573064dd2a14f5026847e755518c8659c9
        );

        // ** Base

        USDC_CBBTC_key_base = _getAndCheckPoolKey(
            IERC20(BConstants.USDC),
            IERC20(BConstants.CBBTC),
            500,
            10,
            0x12d76c5c8ec8edffd3c143995b0aa43fe44a6d71eb9113796272909e54b8e078
        );
    }

    // --- Oracles  --- //

    function getFeedPrice(IAggV3 feed) internal view returns (uint256) {
        (, int256 price, , , ) = feed.latestRoundData();
        return SafeCast.toUint256(price);
    }

    function create_oracle(
        bool _isInvertedPool,
        IAggV3 feedQ,
        IAggV3 feedB,
        uint128 stallThreshQ,
        uint128 stallThreshB
    ) internal returns (IOracle) {
        return _create_oracle(feedQ, feedB, stallThreshQ, stallThreshB, _isInvertedPool, int8(bDec) - int8(qDec));
    }

    function _create_oracle(
        IAggV3 feedQ,
        IAggV3 feedB,
        uint128 stallThreshQ,
        uint128 stallThreshB,
        bool _isInvertedPool,
        int8 decimalsDelta
    ) internal returns (IOracle _oracle) {
        isInvertedPool = _isInvertedPool;
        vm.prank(deployer.addr);
        _oracle = new Oracle(feedB, feedQ, _isInvertedPool, decimalsDelta);
        oracle = _oracle;
        vm.prank(deployer.addr);
        IOracleTest(address(oracle)).setStalenessThresholds(stallThreshB, stallThreshQ);
    }

    function __create_oracle(
        IAggV3 feedB,
        IAggV3 feedQ,
        uint128 stallThreshB,
        uint128 stallThreshQ,
        bool _isInvertedPool,
        int256 decimalsDelta
    ) internal returns (IOracle _oracle) {
        isInvertedPool = _isInvertedPool;
        vm.prank(deployer.addr);
        _oracle = new Oracle(feedB, feedQ, _isInvertedPool, decimalsDelta);
        oracle = _oracle;
        vm.prank(deployer.addr);
        IOracleTest(address(oracle)).setStalenessThresholds(stallThreshB, stallThreshQ);
    }

    function _create_oracle_one_feed(
        IAggV3 feedQ,
        IAggV3 feedB,
        uint128 stalenessThreshold,
        bool _isInvertedPool,
        int8 decimalsDelta
    ) internal returns (IOracle _oracle) {
        isInvertedPool = _isInvertedPool;
        vm.prank(deployer.addr);
        _oracle = new Oracle(feedB, feedQ, _isInvertedPool, decimalsDelta);
        oracle = _oracle;
        vm.prank(deployer.addr);
        IOracleTest(address(oracle)).setStalenessThresholds(stalenessThreshold, stalenessThreshold);
    }

    function mock_latestRoundData(IAggV3 feed, uint256 value) public {
        vm.mockCall(
            address(feed),
            abi.encodeWithSelector(IAggV3.latestRoundData.selector),
            abi.encode(uint80(0), int256(value), uint256(0), uint256(block.timestamp), uint80(0))
        );
    }

    function _getAndCheckPoolKey(
        IERC20 token0,
        IERC20 token1,
        uint24 fee,
        int24 tickSpacing,
        bytes32 _poolId
    ) internal pure returns (PoolKey memory poolKey) {
        _test_currencies_order(address(token0), address(token1));
        poolKey = PoolKey(
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            fee,
            tickSpacing,
            IHooks(address(0))
        );
        PoolId id = poolKey.toId();
        assertEq(PoolId.unwrap(id), _poolId, "PoolId not equal");
    }

    function _test_currencies_order(address token0, address token1) internal pure {
        if (token0 >= token1) revert("Out of order");
    }
}
