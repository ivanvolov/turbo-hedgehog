// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** external imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TestFeed} from "@test/simulations/TestFeed.sol";
import {AggregatorV3Interface as IAggV3} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

// ** contracts
import {DeployUtils} from "../common/DeployUtils.sol";
import {Oracle} from "@src/core/oracles/Oracle.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {TestLib} from "@test/libraries/TestLib.sol";

contract SetPriceTestFeedUNI is DeployUtils {
    using SafeERC20 for IERC20;

    function setUp() public {
        setup_network_specific_addresses_unichain();
        BASE = IERC20(UConstants.USDC);
        QUOTE = IERC20(UConstants.WETH);
        loadActorsUNI();
        loadOracleAddress();
    }

    function run() external {
        IAggV3 feedQ = Oracle(address(oracle)).feedQuote();
        (, int256 price, , , ) = feedQ.latestRoundData();

        TestFeed testFeed = TestFeed(address(feedQ));
        vm.startBroadcast(deployerKey);
        testFeed.updateFeed(4000e18);
        vm.stopBroadcast();

        console.log("feedQ: %s", uint256(price));
    }
}
