// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {FlashLoanBase} from "./FlashLoanBase.sol";

contract EulerFlashLoanAdapter is FlashLoanBase {
    error NotAllowedEulerVault(address account);
    error FlashLoanAssetNotAllowed(address asset);

    // ** EulerV2
    IEulerVault public immutable flVault0;
    IEulerVault public immutable flVault1;
    address public immutable flVault0Asset;
    address public immutable flVault1Asset;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        IEulerVault _flVault0,
        IEulerVault _flVault1
    ) FlashLoanBase(false, _base, _quote, _bDec, _qDec) {
        flVault0 = _flVault0;
        flVault1 = _flVault1;

        flVault0Asset = flVault0.asset();
        flVault1Asset = flVault1.asset();
    }

    function onFlashLoan(bytes calldata _data) external notPaused returns (bytes32) {
        if (msg.sender != address(flVault0) && msg.sender != address(flVault1)) revert NotAllowedEulerVault(msg.sender);
        _onFlashLoan(_data);
        return bytes32(0);
    }

    function _flashLoanSingle(IERC20 asset, uint256 amount, bytes memory _data) internal virtual override {
        getVaultByToken(asset).flashLoan(amount, _data);
    }

    function getVaultByToken(IERC20 token) internal view returns (IEulerVault) {
        if (flVault0Asset == address(token)) return flVault0;
        else if (flVault1Asset == address(token)) return flVault1;
        else revert FlashLoanAssetNotAllowed(address(token));
    }
}
