// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** interfaces
import {IALM} from "./IALM.sol";
import {ILendingAdapter} from "./ILendingAdapter.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {IOracle} from "./IOracle.sol";
import {IRebalanceAdapter} from "./IRebalanceAdapter.sol";
import {ISwapAdapter} from "./ISwapAdapter.sol";

interface IBase {
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    error NotALM(address account);
    error NotRebalanceAdapter(address account);
    error NotModule(address account);
    error NotLendingAdapter(address account);
    error ContractPaused();
    error ContractShutdown();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function oracle() external view returns (IOracle);

    function setComponents(
        IALM _alm,
        ILendingAdapter _lendingAdapter,
        IPositionManager _positionManager,
        IOracle _oracle,
        IRebalanceAdapter _rebalanceAdapter,
        ISwapAdapter _swapAdapter
    ) external;

    function transferOwnership(address newOwner) external;
}
