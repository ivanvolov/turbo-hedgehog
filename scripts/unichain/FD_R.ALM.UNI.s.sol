// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** external imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {DeployUtils} from "../common/DeployUtils.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

contract FirstDepositAndRebalanceALMUNI is DeployUtils {
    using SafeERC20 for IERC20;

    function setUp() public {
        setup_network_specific_addresses_unichain();
        BASE = IERC20(UConstants.USDC);
        QUOTE = IERC20(UConstants.WETH);
        loadActorsUNI();
        loadComponentAddresses(false);
        poolKey = constructPoolKey();
    }

    function run(uint256 action) external {
        if (action == 0) doDeposit();
        else if (action == 1) doRebalance();
    }

    function doDeposit() internal {
        uint256 depositAmount = 224250000000000; // ~ 1$

        uint256 allowance = QUOTE.allowance(depositorAddress, address(alm));
        vm.startBroadcast(depositorKey);

        if (allowance < depositAmount) QUOTE.approve(address(alm), type(uint256).max);
        WETH9.deposit{value: depositAmount}();
        uint256 shares = alm.deposit(depositorAddress, depositAmount, 0);
        console.log("shares: %s", shares);

        vm.stopBroadcast();
    }

    function doRebalance() internal {
        vm.startBroadcast(deployerKey);

        console.log("sqrtPrice hooks %s", hook.sqrtPriceCurrent());
        (uint256 price, uint256 sqrtPriceX96) = oracle.poolPrice();
        console.log("price oracle %s", price);
        console.log("sqrtPriceX96 oracle %s", sqrtPriceX96);
        console.log("TVL: %s", alm.TVL(price));

        (bool isRebalance, uint256 priceThreshold, uint256 auctionTT) = rebalanceAdapter.isRebalanceNeeded(price);
        console.log("isRebalance: %s", isRebalance);
        console.log("priceThreshold: %s", priceThreshold);
        console.log("auctionTriggerTime: %s", auctionTT);

        rebalanceAdapter.rebalance(1e18);
        console.log("sqrtPrice %s", hook.sqrtPriceCurrent());
        console.log("TVL: %s", alm.TVL(price));

        vm.stopBroadcast();
    }
}
