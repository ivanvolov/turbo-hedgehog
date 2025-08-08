// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** external imports
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {FlashLoanBase} from "./FlashLoanBase.sol";

/// @title Euler Flash Loan Adapter
/// @notice Implementation of the flash loan adapter using Euler V2.
contract EulerFlashLoanAdapter is FlashLoanBase {
    error NotAllowedEulerVault(address vault);
    error FlashLoanAssetNotAllowed(address asset);

    IEulerVault public immutable flVaultBase;
    IEulerVault public immutable flVaultQuote;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        IEulerVault _flVaultBase,
        IEulerVault _flVaultQuote
    ) FlashLoanBase(false, _base, _quote) {
        flVaultBase = _flVaultBase;
        flVaultQuote = _flVaultQuote;
    }

    function onFlashLoan(bytes calldata data) external notPaused returns (bytes32) {
        if (msg.sender != address(flVaultBase) && msg.sender != address(flVaultQuote))
            revert NotAllowedEulerVault(msg.sender);
        _onFlashLoan(data);
        return bytes32(0);
    }

    function _flashLoanSingle(bool isBase, uint256 amount, bytes memory data) internal virtual override {
        isBase ? flVaultBase.flashLoan(amount, data) : flVaultQuote.flashLoan(amount, data);
    }
}
