// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract Base is IBase {
    using SafeERC20 for IERC20;

    address public owner;

    address public base;
    address public quote;
    uint8 public bDec;
    uint8 public qDec;

    IALM public alm;
    ILendingAdapter public lendingAdapter;
    IPositionManager public positionManager;
    IOracle public oracle;
    IRebalanceAdapter public rebalanceAdapter;
    ISwapAdapter public swapAdapter;

    constructor(address initialOwner) {
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function setTokens(address _base, address _quote, uint8 _bDec, uint8 _qDec) external onlyOwner {
        if (base != address(0)) revert TokensAlreadyInitialized();

        base = _base;
        quote = _quote;
        bDec = _bDec;
        qDec = _qDec;

        _postSetTokens();
    }

    function _postSetTokens() internal virtual {}

    function setComponents(
        address _alm,
        address _lendingAdapter,
        address _positionManager,
        address _oracle,
        address _rebalanceAdapter,
        address _swapAdapter
    ) external onlyOwner {
        alm = IALM(_alm);
        oracle = IOracle(_oracle);
        rebalanceAdapter = IRebalanceAdapter(_rebalanceAdapter);

        _approveSingle(base, address(lendingAdapter), _lendingAdapter, type(uint256).max);
        _approveSingle(quote, address(lendingAdapter), _lendingAdapter, type(uint256).max);
        lendingAdapter = ILendingAdapter(_lendingAdapter);

        _approveSingle(base, address(positionManager), _positionManager, type(uint256).max);
        _approveSingle(quote, address(positionManager), _positionManager, type(uint256).max);
        positionManager = IPositionManager(_positionManager);

        _approveSingle(base, address(swapAdapter), _swapAdapter, type(uint256).max);
        _approveSingle(quote, address(swapAdapter), _swapAdapter, type(uint256).max);
        swapAdapter = ISwapAdapter(_swapAdapter);
    }

    function _approveSingle(address token, address moduleOld, address moduleNew, uint256 amount) internal {
        if (moduleOld != address(0) && moduleOld != address(this)) IERC20(token).forceApprove(moduleOld, 0);
        if (moduleNew != address(this)) IERC20(token).forceApprove(moduleNew, amount);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, owner);
    }

    function otherToken(address token) internal view returns (address) {
        return token == base ? quote : base;
    }

    // --- Modifiers --- //

    modifier onlyOwner() {
        if (owner != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
        _;
    }

    // @dev Only the ALM may call this function
    modifier onlyALM() {
        if (msg.sender != address(alm)) revert NotALM();
        _;
    }

    /// @dev Only the rebalance adapter may call this function
    modifier onlyRebalanceAdapter() {
        if (msg.sender != address(rebalanceAdapter)) revert NotRebalanceAdapter();
        _;
    }

    /// @dev Only the lending adapter may call this function
    modifier onlyLendingAdapter() {
        if (msg.sender != address(lendingAdapter)) revert NotLendingAdapter();
        _;
    }

    /// @dev Only modules may call this function
    modifier onlyModule() {
        if (
            msg.sender != address(alm) &&
            msg.sender != address(lendingAdapter) &&
            msg.sender != address(positionManager) &&
            msg.sender != address(rebalanceAdapter) &&
            msg.sender != address(swapAdapter)
        ) revert NotModule();

        _;
    }

    /// @dev Only allows execution when the contract is not paused
    modifier notPaused() {
        if (alm.paused()) revert ContractPaused();
        _;
    }

    /// @dev Only allows execution when the contract is not shut down
    modifier notShutdown() {
        if (alm.shutdown()) revert ContractShutdown();
        _;
    }
}
