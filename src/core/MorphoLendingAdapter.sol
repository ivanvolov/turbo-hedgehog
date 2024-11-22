// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import "@src/interfaces/ILendingAdapter.sol";
import {IMorpho, Id, Position} from "@forks/morpho/IMorpho.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

contract MorphoLendingAdapter is Ownable, ILendingAdapter {
    IMorpho public constant morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    Id public depositUSDCmId;
    Id public borrowUSDCmId;

    mapping(address => bool) public authorizedCallers;

    constructor() Ownable(msg.sender) {
        WETH.approve(address(morpho), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);
    }

    function setDepositUSDCmId(Id _depositUSDCmId) external onlyOwner {
        depositUSDCmId = _depositUSDCmId;
    }

    function setBorrowUSDCmId(Id _borrowUSDCmId) external onlyOwner {
        borrowUSDCmId = _borrowUSDCmId;
    }

    function addAuthorizedCaller(address _caller) external onlyOwner {
        authorizedCallers[_caller] = true;
    }

    // Borrow market

    function getBorrowed() external view returns (uint256) {
        return
            MorphoBalancesLib.expectedBorrowAssets(
                morpho,
                morpho.idToMarketParams(borrowUSDCmId),
                address(this)
            );
    }

    function borrow(uint256 amountUSDC) external onlyAuthorizedCaller {
        morpho.borrow(
            morpho.idToMarketParams(borrowUSDCmId),
            amountUSDC,
            0,
            address(this),
            msg.sender
        );
    }

    function repay(uint256 amountUSDC) external onlyAuthorizedCaller {
        USDC.transferFrom(msg.sender, address(this), amountUSDC);
        morpho.repay(
            morpho.idToMarketParams(borrowUSDCmId),
            amountUSDC,
            0,
            address(this),
            ""
        );
    }

    function getCollateral() external view returns (uint256) {
        Position memory p = morpho.position(borrowUSDCmId, address(this));
        return p.collateral;
    }

    function removeCollateral(uint256 amount) external onlyAuthorizedCaller {
        morpho.withdrawCollateral(
            morpho.idToMarketParams(borrowUSDCmId),
            amount,
            address(this),
            msg.sender
        );
    }

    function addCollateral(uint256 amount) external onlyAuthorizedCaller {
        WETH.transferFrom(msg.sender, address(this), amount);
        morpho.supplyCollateral(
            morpho.idToMarketParams(borrowUSDCmId),
            amount,
            address(this),
            ""
        );
    }

    // Provide market

    function getSupplied() external view returns (uint256) {
        return
            MorphoBalancesLib.expectedSupplyAssets(
                morpho,
                morpho.idToMarketParams(depositUSDCmId),
                address(this)
            );
    }

    function supply(uint256 amountUsdc) external onlyAuthorizedCaller {
        USDC.transferFrom(msg.sender, address(this), amountUsdc);
        morpho.supply(
            morpho.idToMarketParams(depositUSDCmId),
            amountUsdc,
            0,
            address(this),
            ""
        );
    }

    function withdraw(uint256 amountUsdc) external onlyAuthorizedCaller {
        morpho.withdraw(
            morpho.idToMarketParams(depositUSDCmId),
            amountUsdc,
            0,
            address(this),
            msg.sender
        );
    }

    function syncDeposit() external {
        morpho.accrueInterest(morpho.idToMarketParams(depositUSDCmId));
    }

    function syncBorrow() external {
        morpho.accrueInterest(morpho.idToMarketParams(borrowUSDCmId));
    }

    // Helpers

    modifier onlyAuthorizedCaller() {
        require(
            authorizedCallers[msg.sender] == true,
            "Caller is not authorized V4 pool"
        );
        _;
    }
}
// TODO: remove in production
// LINKS: https://docs.morpho.org/morpho/tutorials/manage-positions
