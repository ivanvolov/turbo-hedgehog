// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** Euler imports
import {IEulerVault} from "../../interfaces/lendingAdapters/IEulerVault.sol";

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {IFlashLoanAdapter, IFlashLoanReceiver} from "../../interfaces/IFlashLoanAdapter.sol";

contract EulerFlashLoanAdapter is Base, IFlashLoanAdapter {
    using SafeERC20 for IERC20;

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
    ) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        flVault0 = _flVault0;
        flVault1 = _flVault1;

        flVault0Asset = flVault0.asset();
        flVault1Asset = flVault1.asset();
    }

    // ** Flashloan

    function flashLoanSingle(IERC20 asset, uint256 amount, bytes calldata data) public onlyModule notPaused {
        bytes memory _data = abi.encode(0, msg.sender, asset, amount, data);
        getVaultByToken(asset).flashLoan(amount, _data);
    }

    function flashLoanTwoTokens(
        IERC20 asset0,
        uint256 amount0,
        IERC20 asset1,
        uint256 amount1,
        bytes calldata data
    ) public onlyModule notPaused {
        bytes memory _data = abi.encode(2, msg.sender, asset0, amount0, asset1, amount1, data);
        getVaultByToken(asset0).flashLoan(amount0, _data);
    }

    function onFlashLoan(bytes calldata _data) external notPaused returns (bytes32) {
        require(msg.sender == address(flVault0) || msg.sender == address(flVault1), "M0");
        uint8 loanType = abi.decode(_data, (uint8));

        if (loanType == 0) {
            (, address sender, IERC20 asset, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, IERC20, uint256, bytes)
            );

            asset.safeTransfer(sender, amount);
            IFlashLoanReceiver(sender).onFlashLoanSingle(asset, amount, data);
            asset.safeTransferFrom(sender, msg.sender, amount);
        } else if (loanType == 2) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));
            bytes memory __data = abi.encode(uint8(1), sender, asset0, amount0, asset1, amount1, data);

            asset0.safeTransfer(sender, amount0);
            getVaultByToken(asset1).flashLoan(amount1, __data);
            asset0.safeTransferFrom(sender, msg.sender, amount0);
        } else if (loanType == 1) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));

            asset1.safeTransfer(sender, amount1);
            IFlashLoanReceiver(sender).onFlashLoanTwoTokens(asset0, amount0, asset1, amount1, data);
            asset1.safeTransferFrom(sender, msg.sender, amount1);
        } else revert("M2");

        return "";
    }

    function getVaultByToken(IERC20 token) public view returns (IEulerVault) {
        if (flVault0Asset == address(token)) return flVault0;
        else if (flVault1Asset == address(token)) return flVault1;
        else revert("M1");
    }
}
