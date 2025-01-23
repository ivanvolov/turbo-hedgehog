// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** libraries
import {IMorpho, Id, Position} from "@forks/morpho/IMorpho.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";

// ** contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ** interfaces
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";

contract MorphoLendingAdapter is Ownable, ILendingAdapter {
    IMorpho public constant morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    Id public shortMId;
    Id public longMId;

    mapping(address => bool) public authorizedCallers;

    constructor() Ownable(msg.sender) {
        WETH.approve(address(morpho), type(uint256).max);
        USDC.approve(address(morpho), type(uint256).max);
    }

    function setShortMId(Id _shortMId) external onlyOwner {
        shortMId = _shortMId;
    }

    function setLongMId(Id _longMId) external onlyOwner {
        longMId = _longMId;
    }

    function addAuthorizedCaller(address _caller) external onlyOwner {
        authorizedCallers[_caller] = true;
    }

    // Long market

    function getBorrowedLong() external view returns (uint256) {
        return MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(longMId), address(this));
    }

    function borrowLong(uint256 amountUSDC) external onlyAuthorizedCaller {
        morpho.borrow(morpho.idToMarketParams(longMId), amountUSDC, 0, address(this), msg.sender);
    }

    function repayLong(uint256 amountUSDC) external onlyAuthorizedCaller {
        USDC.transferFrom(msg.sender, address(this), amountUSDC);
        morpho.repay(morpho.idToMarketParams(longMId), amountUSDC, 0, address(this), "");
    }

    function getCollateralLong() external view returns (uint256) {
        Position memory p = morpho.position(longMId, address(this));
        return p.collateral;
    }

    function removeCollateralLong(uint256 amountWETH) external onlyAuthorizedCaller {
        morpho.withdrawCollateral(morpho.idToMarketParams(longMId), amountWETH, address(this), msg.sender);
    }

    function addCollateralLong(uint256 amountWETH) external onlyAuthorizedCaller {
        WETH.transferFrom(msg.sender, address(this), amountWETH);
        morpho.supplyCollateral(morpho.idToMarketParams(longMId), amountWETH, address(this), "");
    }

    // Short market

    function getBorrowedShort() external view returns (uint256) {
        return MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(shortMId), address(this));
    }

    function borrowShort(uint256 amountWETH) external onlyAuthorizedCaller {
        morpho.borrow(morpho.idToMarketParams(shortMId), amountWETH, 0, address(this), msg.sender);
    }

    function repayShort(uint256 amountWETH) external onlyAuthorizedCaller {
        USDC.transferFrom(msg.sender, address(this), amountWETH);
        morpho.repay(morpho.idToMarketParams(shortMId), amountWETH, 0, address(this), "");
    }

    function getCollateralShort() external view returns (uint256) {
        Position memory p = morpho.position(shortMId, address(this));
        return p.collateral;
    }

    function removeCollateralShort(uint256 amountUSDC) external onlyAuthorizedCaller {
        morpho.withdrawCollateral(morpho.idToMarketParams(shortMId), amountUSDC, address(this), msg.sender);
    }

    function addCollateralShort(uint256 amountUSDC) external onlyAuthorizedCaller {
        USDC.transferFrom(msg.sender, address(this), amountUSDC);
        morpho.supplyCollateral(morpho.idToMarketParams(shortMId), amountUSDC, address(this), "");
    }

    // Helpers
    function setTokens(
        address _baseToken,
        address _quoteToken,
        uint8 _baseDec,
        uint8 _quoteDec
    ) external override onlyOwner {
        //TODO: implement it for morpho
    }

    function syncLong() external {
        morpho.accrueInterest(morpho.idToMarketParams(longMId));
    }

    function syncShort() external {
        morpho.accrueInterest(morpho.idToMarketParams(shortMId));
    }

    modifier onlyAuthorizedCaller() {
        require(authorizedCallers[msg.sender] == true, "Caller is not authorized V4 pool");
        _;
    }
}
// TODO: remove in production
// LINKS: https://docs.morpho.org/morpho/tutorials/manage-positions
