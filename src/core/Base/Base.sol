// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** external imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** interfaces
import {IALM} from "../../interfaces/IALM.sol";
import {IBaseStrategyHook} from "../../interfaces/IBaseStrategyHook.sol";
import {ILendingAdapter} from "../../interfaces/ILendingAdapter.sol";
import {IFlashLoanAdapter} from "../../interfaces/IFlashLoanAdapter.sol";
import {IPositionManager} from "../../interfaces/IPositionManager.sol";
import {IOracle} from "../../interfaces/IOracle.sol";
import {IRebalanceAdapter} from "../../interfaces/IRebalanceAdapter.sol";
import {ISwapAdapter} from "../../interfaces/ISwapAdapter.sol";
import {IBase} from "../../interfaces/IBase.sol";

/// @title Base
/// @notice Abstract contract that serves as the base for all modules and adapters.
abstract contract Base is IBase {
    using SafeERC20 for IERC20;

    enum ComponentType {
        ALM,
        HOOK,
        REBALANCE_ADAPTER,
        POSITION_MANAGER,
        EXTERNAL_ADAPTER
    }

    ComponentType public immutable componentType;
    address public owner;

    IERC20 public immutable BASE;
    IERC20 public immutable QUOTE;

    IALM public alm;
    IBaseStrategyHook public hook;
    ILendingAdapter public lendingAdapter;
    IFlashLoanAdapter public flashLoanAdapter;
    IPositionManager public positionManager;
    IOracle public oracle;
    IRebalanceAdapter public rebalanceAdapter;
    ISwapAdapter public swapAdapter;

    constructor(ComponentType _componentType, address initialOwner, IERC20 _base, IERC20 _quote) {
        componentType = _componentType;
        BASE = _base;
        QUOTE = _quote;

        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function setComponents(
        IALM _alm,
        IBaseStrategyHook _hook,
        ILendingAdapter _lendingAdapter,
        IFlashLoanAdapter _flashLoanAdapter,
        IPositionManager _positionManager,
        IOracle _oracle,
        IRebalanceAdapter _rebalanceAdapter,
        ISwapAdapter _swapAdapter
    ) external onlyOwner {
        alm = _alm;
        hook = _hook;
        oracle = _oracle;
        rebalanceAdapter = _rebalanceAdapter;

        if (componentType == ComponentType.POSITION_MANAGER) {
            switchApproval(address(lendingAdapter), address(_lendingAdapter));
        } else if (componentType == ComponentType.HOOK) {
            switchApproval(address(lendingAdapter), address(_lendingAdapter));
            switchApproval(address(positionManager), address(_positionManager));
        } else if (componentType == ComponentType.ALM || componentType == ComponentType.REBALANCE_ADAPTER) {
            switchApproval(address(lendingAdapter), address(_lendingAdapter));
            switchApproval(address(flashLoanAdapter), address(_flashLoanAdapter));
            switchApproval(address(swapAdapter), address(_swapAdapter));
        }

        lendingAdapter = _lendingAdapter;
        flashLoanAdapter = _flashLoanAdapter;
        swapAdapter = _swapAdapter;
        positionManager = _positionManager;
    }

    function switchApproval(address moduleOld, address moduleNew) internal {
        if (moduleOld == moduleNew) return;
        if (moduleOld != address(0)) {
            BASE.forceApprove(moduleOld, 0);
            QUOTE.forceApprove(moduleOld, 0);
        }
        BASE.forceApprove(moduleNew, type(uint256).max);
        QUOTE.forceApprove(moduleNew, type(uint256).max);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (owner == newOwner) return;
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

    /// @dev Only the ALM may call this function.
    modifier onlyALM() {
        if (msg.sender != address(alm)) revert NotALM(msg.sender);
        _;
    }

    modifier onlyHook() {
        if (msg.sender != address(hook)) revert NotHook(msg.sender);
        _;
    }

    /// @dev Only the rebalance adapter may call this function.
    modifier onlyRebalanceAdapter() {
        if (msg.sender != address(rebalanceAdapter)) revert NotRebalanceAdapter(msg.sender);
        _;
    }

    /// @dev Only the flash loan adapter may call this function.
    modifier onlyFlashLoanAdapter() {
        if (msg.sender != address(flashLoanAdapter)) revert NotFlashLoanAdapter(msg.sender);
        _;
    }

    /// @dev Only modules may call this function.
    modifier onlyModule() {
        if (
            msg.sender != address(alm) &&
            msg.sender != address(hook) &&
            msg.sender != address(rebalanceAdapter) &&
            msg.sender != address(positionManager)
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

    /// @notice Restricts function execution when contract is not active.
    /// @dev Allows execution when status equals 0 (active).
    /// @dev Reverts with ContractNotActive when status is paused (1) or shutdown (2).
    modifier onlyActive() {
        if (alm.status() != 0) revert ContractNotActive();
        _;
    }
}
