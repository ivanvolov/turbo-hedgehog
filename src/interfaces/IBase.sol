// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";

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
        address _alm,
        address _lendingAdapter,
        address _positionManager,
        address _oracle,
        address _rebalanceAdapter,
        address _swapAdapter
    ) external;

    function transferOwnership(address newOwner) external;
}
