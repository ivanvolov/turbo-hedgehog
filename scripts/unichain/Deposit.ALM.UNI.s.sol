// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** external imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {DeployALM} from "../common/DeployALM.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

contract DepositAndRebalanceALMUNI is DeployALM {
    using SafeERC20 for IERC20;

    function setUp() public {
        setup_network_specific_addresses_unichain();
        BASE = IERC20(UConstants.USDC);
        QUOTE = IERC20(UConstants.WETH);
        loadActorsUNI();
        loadComponentAddresses();
        poolKey = constructPoolKey();
    }

    uint256 public mainnetDepositAmount = 224250000000000; // ~ 1$
    uint256 public testDepositAmount = 1 ether; // ~ 3800$

    function run(uint256 depositSize) external {
        if (action == 0) {
            // Mainnet deposit small size
            doDeposit(mainnetDepositAmount);
        } else if (action == 1) {
            // Test deposit large size
            dealETH(depositorAddress, testDepositAmount);
            doDeposit(testDepositAmount);
        } else revert("Invalid action");
    }

    function doDeposit(uint256 depositAmount) internal {
        uint256 allowance = QUOTE.allowance(depositorAddress, address(alm));
        vm.startBroadcast(depositorKey);

        if (allowance < depositAmount) QUOTE.approve(address(alm), type(uint256).max);
        WETH9.deposit{value: depositAmount}();
        uint256 shares = alm.deposit(depositorAddress, depositAmount, 0);
        console.log("shares: %s", shares);

        vm.stopBroadcast();
    }
}
