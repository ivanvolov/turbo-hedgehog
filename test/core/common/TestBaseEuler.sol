// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** contracts
import {TestBaseShortcuts} from "./TestBaseShortcuts.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {EulerFlashLoanAdapter} from "@src/core/flashLoanAdapters/EulerFlashLoanAdapter.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

// ** interfaces
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

abstract contract TestBaseEuler is TestBaseShortcuts {
    using SafeERC20 for IERC20;

    function create_lending_adapter_euler_USDC_WETH() internal {
        create_lending_adapter_euler(MConstants.eulerUSDCVault1, 0, MConstants.eulerWETHVault1, 0);
    }

    function create_flash_loan_adapter_euler_USDC_WETH() internal {
        create_flash_loan_adapter_euler(MConstants.eulerUSDCVault2, 0, MConstants.eulerWETHVault2, 0);
    }

    function create_lending_adapter_euler_USDT_USDC() internal {
        create_lending_adapter_euler(MConstants.eulerUSDCVault1, 10e12, MConstants.eulerUSDTVault1, 10e12);
    }

    function create_flash_loan_adapter_euler_USDT_USDC() internal {
        create_flash_loan_adapter_euler(MConstants.eulerUSDCVault2, 10e12, MConstants.eulerUSDTVault2, 10e12);
    }

    function create_lending_adapter_euler_USDC_WETH_unichain() internal returns (ILendingAdapter) {
        vm.prank(deployer.addr);
        lendingAdapter = new EulerLendingAdapter(
            BASE,
            QUOTE,
            UConstants.EULER_VAULT_CONNECT,
            UConstants.eulerUSDCVault1,
            UConstants.eulerWETHVault1,
            UConstants.merklRewardsDistributor,
            UConstants.rEUL
        );
        return lendingAdapter;
    }

    function create_lending_adapter_euler_USDT_WETH_unichain() internal returns (ILendingAdapter) {
        vm.prank(deployer.addr);
        lendingAdapter = new EulerLendingAdapter(
            BASE,
            QUOTE,
            UConstants.EULER_VAULT_CONNECT,
            UConstants.eulerUSDTVault1,
            UConstants.eulerWETHVault1,
            UConstants.merklRewardsDistributor,
            UConstants.rEUL
        );
        return lendingAdapter;
    }

    function create_lending_adapter_euler_USDC_USDT_unichain() internal returns (ILendingAdapter) {
        vm.prank(deployer.addr);
        lendingAdapter = new EulerLendingAdapter(
            BASE,
            QUOTE,
            UConstants.EULER_VAULT_CONNECT,
            UConstants.eulerUSDCVault1,
            UConstants.eulerUSDTVault1,
            UConstants.merklRewardsDistributor,
            UConstants.rEUL
        );
        return lendingAdapter;
    }

    function create_lending_adapter_euler_USDC_BTC_unichain() internal returns (ILendingAdapter) {
        vm.prank(deployer.addr);
        lendingAdapter = new EulerLendingAdapter(
            BASE,
            QUOTE,
            UConstants.EULER_VAULT_CONNECT,
            UConstants.eulerUSDCVault1,
            UConstants.eulerWBTCVault1,
            UConstants.merklRewardsDistributor,
            UConstants.rEUL
        );
        return lendingAdapter;
    }

    function create_lending_adapter_euler_WETH_WSTETH_unichain() internal returns (ILendingAdapter) {
        vm.prank(deployer.addr);
        lendingAdapter = new EulerLendingAdapter(
            BASE,
            QUOTE,
            UConstants.EULER_VAULT_CONNECT,
            UConstants.eulerWETHVault1,
            UConstants.eulerWSTETHVault1,
            UConstants.merklRewardsDistributor,
            UConstants.rEUL
        );
        return lendingAdapter;
    }

    function create_lending_adapter_euler(
        IEulerVault _vault0,
        uint256 deposit0,
        IEulerVault _vault1,
        uint256 deposit1
    ) internal {
        vm.prank(deployer.addr);
        lendingAdapter = new EulerLendingAdapter(
            BASE,
            QUOTE,
            MConstants.EULER_VAULT_CONNECT,
            _vault0,
            _vault1,
            MConstants.merklRewardsDistributor,
            MConstants.rEUL
        );
        _deposit_to_euler(_vault0, deposit0);
        _deposit_to_euler(_vault1, deposit1);
    }

    function create_flash_loan_adapter_euler(
        IEulerVault _flVault0,
        uint256 deposit0,
        IEulerVault _flVault1,
        uint256 deposit1
    ) internal {
        vm.prank(deployer.addr);
        flashLoanAdapter = new EulerFlashLoanAdapter(BASE, QUOTE, _flVault0, _flVault1);
        _deposit_to_euler(_flVault0, deposit0);
        _deposit_to_euler(_flVault1, deposit1);
    }

    function _deposit_to_euler(IEulerVault vault, uint256 toSupply) internal {
        if (toSupply == 0) return;
        address asset = vault.asset();
        deal(asset, address(marketMaker.addr), toSupply);

        vm.startPrank(marketMaker.addr);
        IERC20(asset).forceApprove(address(vault), type(uint256).max);
        vault.mint(vault.convertToShares(toSupply), marketMaker.addr);
        vm.stopPrank();
    }
}
