// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** contracts
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {IBase} from "@src/interfaces/IBase.sol";

abstract contract Base is IBase {
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    error NotALM();
    error NotRebalanceAdapter();
    error NotModule();

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

    function _postSetTokens() internal virtual {}

    function setComponents(
        address _alm,
        address _lendingAdapter,
        address _positionManager,
        address _oracle,
        address _rebalanceAdapter
    ) external onlyOwner {
        alm = IALM(_alm);
        oracle = IOracle(_oracle);
        rebalanceAdapter = IRebalanceAdapter(_rebalanceAdapter);

        ALMBaseLib.approveSingle(token0, address(lendingAdapter), _lendingAdapter, type(uint256).max);
        ALMBaseLib.approveSingle(token1, address(lendingAdapter), _lendingAdapter, type(uint256).max);
        lendingAdapter = ILendingAdapter(_lendingAdapter);

        ALMBaseLib.approveSingle(token0, address(positionManager), _positionManager, type(uint256).max);
        ALMBaseLib.approveSingle(token1, address(positionManager), _positionManager, type(uint256).max);
        positionManager = IPositionManager(_positionManager);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, owner);
    }

    // --- Modifiers ---

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
            msg.sender != address(rebalanceAdapter)
        ) revert NotModule();

        _;
    }
}
