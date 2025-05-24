// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {ALMMathLib} from "../../libraries/ALMMathLib.sol";

// ** interfaces
import {IALM} from "../../interfaces/IALM.sol";
import {ILendingAdapter} from "../../interfaces/ILendingAdapter.sol";
import {IFlashLoanAdapter} from "../../interfaces/IFlashLoanAdapter.sol";
import {IPositionManager} from "../../interfaces/IPositionManager.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {IRebalanceAdapter} from "../../interfaces/IRebalanceAdapter.sol";
import {ISwapAdapter} from "../../interfaces/swapAdapters/ISwapAdapter.sol";
import {IBase} from "../../interfaces/IBase.sol";

abstract contract Base is IBase {
    using SafeERC20 for IERC20;

    address public owner;

    IERC20 public immutable BASE;
    IERC20 public immutable QUOTE;
    uint8 public immutable bDec;
    uint8 public immutable qDec;
    uint8 public immutable decimalsDelta;

    IALM public alm;
    ILendingAdapter public lendingAdapter;
    IFlashLoanAdapter public flashLoanAdapter;
    IPositionManager public positionManager;
    IOracle public oracle;
    IRebalanceAdapter public rebalanceAdapter;
    ISwapAdapter public swapAdapter;

    constructor(address initialOwner, IERC20 _base, IERC20 _quote, uint8 _bDec, uint8 _qDec) {
        BASE = _base;
        QUOTE = _quote;
        bDec = _bDec;
        qDec = _qDec;
        decimalsDelta = uint8(ALMMathLib.absSub(bDec, qDec));

        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function setComponents(
        IALM _alm,
        ILendingAdapter _lendingAdapter,
        IFlashLoanAdapter _flashLoanAdapter,
        IPositionManager _positionManager,
        IOracle _oracle,
        IRebalanceAdapter _rebalanceAdapter,
        ISwapAdapter _swapAdapter
    ) external onlyOwner {
        alm = IALM(_alm);
        oracle = IOracle(_oracle);
        rebalanceAdapter = IRebalanceAdapter(_rebalanceAdapter);

        _approveSingle(BASE, address(lendingAdapter), address(_lendingAdapter), type(uint256).max);
        _approveSingle(QUOTE, address(lendingAdapter), address(_lendingAdapter), type(uint256).max);
        lendingAdapter = _lendingAdapter;

        _approveSingle(BASE, address(flashLoanAdapter), address(_flashLoanAdapter), type(uint256).max);
        _approveSingle(QUOTE, address(flashLoanAdapter), address(_flashLoanAdapter), type(uint256).max);
        flashLoanAdapter = _flashLoanAdapter;

        _approveSingle(BASE, address(positionManager), address(_positionManager), type(uint256).max);
        _approveSingle(QUOTE, address(positionManager), address(_positionManager), type(uint256).max);
        positionManager = _positionManager;

        _approveSingle(BASE, address(swapAdapter), address(_swapAdapter), type(uint256).max);
        _approveSingle(QUOTE, address(swapAdapter), address(_swapAdapter), type(uint256).max);
        swapAdapter = _swapAdapter;
    }

    function _approveSingle(IERC20 token, address moduleOld, address moduleNew, uint256 amount) internal {
        if (moduleOld != address(0) && moduleOld != address(this) && moduleOld != moduleNew)
            token.forceApprove(moduleOld, 0);
        if (moduleNew != address(this)) token.forceApprove(moduleNew, amount);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ** Modifiers

    modifier onlyOwner() {
        if (owner != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
        _;
    }

    /// @dev Only the ALM may call this function
    modifier onlyALM() {
        if (msg.sender != address(alm)) revert NotALM(msg.sender);
        _;
    }

    /// @dev Only the rebalance adapter may call this function
    modifier onlyRebalanceAdapter() {
        if (msg.sender != address(rebalanceAdapter)) revert NotRebalanceAdapter(msg.sender);
        _;
    }

    /// @dev Only the flash loan adapter may call this function
    modifier onlyFlashLoanAdapter() {
        if (msg.sender != address(flashLoanAdapter)) revert NotFlashLoanAdapter(msg.sender);
        _;
    }

    /// @dev Only modules may call this function
    modifier onlyModule() {
        if (
            msg.sender != address(alm) &&
            msg.sender != address(lendingAdapter) &&
            msg.sender != address(flashLoanAdapter) &&
            msg.sender != address(positionManager) &&
            msg.sender != address(rebalanceAdapter) &&
            msg.sender != address(swapAdapter)
        ) revert NotModule(msg.sender);

        _;
    }

    /// @notice Restricts function execution when contract is paused.
    /// @dev Allows execution when status is active (0) or shutdown (2).
    /// @dev Reverts with ContractPaused when status equals 1 (paused).
    modifier notPaused() {
        if (alm.status() == 1) revert ContractPaused();
        _;
    }

    /// @notice Restricts function execution to active state only.
    /// @dev Only allows execution when status equals 0 (active).
    /// @dev Reverts with ContractNotActive when status is paused (1) or shutdown (2).
    modifier onlyActive() {
        if (alm.status() != 0) revert ContractNotActive();
        _;
    }
}
