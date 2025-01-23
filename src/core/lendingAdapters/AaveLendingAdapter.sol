// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** Aave imports
import {IPool} from "@aave-core-v3/contracts/interfaces/IPool.sol";
import {IAaveOracle} from "@aave-core-v3/contracts/interfaces/IAaveOracle.sol";
import {IPoolAddressesProvider} from "@aave-core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPoolDataProvider} from "@aave-core-v3/contracts/interfaces/IPoolDataProvider.sol";

// ** libraries
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ** interfaces
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";

contract AaveLendingAdapter is Ownable, ILendingAdapter {
    using TokenWrapperLib for uint256;

    // ** AaveV3
    IPoolAddressesProvider constant provider = IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);

    address public baseToken;
    address public quoteToken;
    uint8 public baseDec;
    uint8 public quoteDec;

    mapping(address => bool) public authorizedCallers;

    constructor() Ownable(msg.sender) {}

    function setTokens(
        address _baseToken,
        address _quoteToken,
        uint8 _baseDec,
        uint8 _quoteDec
    ) external override onlyOwner {
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        baseDec = _baseDec;
        quoteDec = _quoteDec;

        IERC20(quoteToken).approve(getPool(), type(uint256).max);
        IERC20(baseToken).approve(getPool(), type(uint256).max);
    }

    function getPool() public view returns (address) {
        return provider.getPool();
    }

    function addAuthorizedCaller(address _caller) external onlyOwner {
        authorizedCallers[_caller] = true;
    }

    // ** Long market

    function getBorrowedLong() external view returns (uint256) {
        (, , address variableDebtTokenAddress) = getAssetAddresses(baseToken);
        return IERC20(variableDebtTokenAddress).balanceOf(address(this)).wrap(baseDec);
    }

    function borrowLong(uint256 amount) external onlyAuthorizedCaller {
        IPool(getPool()).borrow(baseToken, amount.unwrap(baseDec), 2, 0, address(this)); // Interest rate mode: 2 = variable
        IERC20(baseToken).transfer(msg.sender, amount.unwrap(baseDec));
    }

    function repayLong(uint256 amount) external onlyAuthorizedCaller {
        IERC20(baseToken).transferFrom(msg.sender, address(this), amount.unwrap(baseDec));
        IPool(getPool()).repay(baseToken, amount.unwrap(baseDec), 2, address(this));
    }

    function getCollateralLong() external view returns (uint256) {
        (address aTokenAddress, , ) = getAssetAddresses(quoteToken);
        return IERC20(aTokenAddress).balanceOf(address(this)).wrap(quoteDec);
    }

    function removeCollateralLong(uint256 amount) external onlyAuthorizedCaller {
        IPool(getPool()).withdraw(quoteToken, amount.unwrap(quoteDec), msg.sender);
    }

    function addCollateralLong(uint256 amount) external onlyAuthorizedCaller {
        IERC20(quoteToken).transferFrom(msg.sender, address(this), amount.unwrap(quoteDec));
        IPool(getPool()).supply(quoteToken, amount.unwrap(quoteDec), address(this), 0);
    }

    // ** Short market

    function getBorrowedShort() external view returns (uint256) {
        (, , address variableDebtTokenAddress) = getAssetAddresses(quoteToken);
        return IERC20(variableDebtTokenAddress).balanceOf(address(this)).wrap(quoteDec);
    }

    function borrowShort(uint256 amount) external onlyAuthorizedCaller {
        IPool(getPool()).borrow(quoteToken, amount.unwrap(quoteDec), 2, 0, address(this)); // Interest rate mode: 2 = variable
        IERC20(quoteToken).transfer(msg.sender, amount.unwrap(quoteDec));
    }

    function repayShort(uint256 amount) external onlyAuthorizedCaller {
        IERC20(quoteToken).transferFrom(msg.sender, address(this), amount.unwrap(quoteDec));
        IPool(getPool()).repay(quoteToken, amount.unwrap(quoteDec), 2, address(this));
    }

    function getCollateralShort() external view returns (uint256) {
        (address aTokenAddress, , ) = getAssetAddresses(baseToken);
        return IERC20(aTokenAddress).balanceOf(address(this)).wrap(baseDec);
    }

    function removeCollateralShort(uint256 amount) external onlyAuthorizedCaller {
        IPool(getPool()).withdraw(baseToken, amount.unwrap(baseDec), msg.sender);
    }

    function addCollateralShort(uint256 amount) external onlyAuthorizedCaller {
        IERC20(baseToken).transferFrom(msg.sender, address(this), amount.unwrap(baseDec));
        IPool(getPool()).supply(baseToken, amount.unwrap(baseDec), address(this), 0);
    }

    // ** Helpers

    function getAssetAddresses(address underlying) public view returns (address, address, address) {
        return IPoolDataProvider(provider.getPoolDataProvider()).getReserveTokensAddresses(underlying);
    }

    function syncLong() external {}

    function syncShort() external {}

    modifier onlyAuthorizedCaller() {
        require(authorizedCallers[msg.sender] == true, "Caller is not authorized V4 pool");
        _;
    }
}
