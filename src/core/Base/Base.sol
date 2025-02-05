// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract Base is IBase {
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    error NotALM();
    error NotRebalanceAdapter();
    error NotModule();
    error ContractPaused();
    error ContractShutdown();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address public owner;

    address public token0;
    address public token1;
    uint8 public t0Dec;
    uint8 public t1Dec;

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

    function setTokens(address _token0, address _token1, uint8 _t0Dec, uint8 _t1Dec) external onlyOwner {
        token0 = _token0;
        token1 = _token1;
        t0Dec = _t0Dec;
        t1Dec = _t1Dec;

        _postSetTokens();
    }

    function _postSetTokens() internal virtual {} // TODO: Maybe do "only one approve" here on all tokens in the child contracts like with modules

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

        _approveSingle(token0, address(lendingAdapter), _lendingAdapter, type(uint256).max);
        _approveSingle(token1, address(lendingAdapter), _lendingAdapter, type(uint256).max);
        lendingAdapter = ILendingAdapter(_lendingAdapter);

        _approveSingle(token0, address(positionManager), _positionManager, type(uint256).max);
        _approveSingle(token1, address(positionManager), _positionManager, type(uint256).max);
        positionManager = IPositionManager(_positionManager);

        _approveSingle(token0, address(swapAdapter), _swapAdapter, type(uint256).max);
        _approveSingle(token1, address(swapAdapter), _swapAdapter, type(uint256).max);
        swapAdapter = ISwapAdapter(_swapAdapter);
    }

    function _approveSingle(address token, address moduleOld, address moduleNew, uint256 amount) internal {
        if (moduleOld != address(0) && moduleOld != address(this)) IERC20(token).approve(moduleOld, 0);
        if (moduleNew != address(this)) IERC20(token).approve(moduleNew, amount);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, owner);
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
