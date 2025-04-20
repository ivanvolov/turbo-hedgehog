// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";

interface IBase {
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    error NotALM(address account);
    error NotRebalanceAdapter(address account);
    error NotModule(address account);
    error NotLendingAdapter(address account);
    error ContractPaused();
    error ContractShutdown();
    error TokensAlreadyInitialized();

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function oracle() external view returns (IOracle);

    function setTokens(address _base, address _quote, uint8 _t0Dec, uint8 _t1Dec) external;

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
