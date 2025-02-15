// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IEulerVault {
    function mint(uint256 amount, address receiver) external returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function borrow(uint256 amount, address receiver) external returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function debtOf(address account) external view returns (uint256);

    function repay(uint256 amount, address receiver) external returns (uint256);

    function withdraw(uint256 amount, address receiver, address owner) external returns (uint256);

    function flashLoan(uint256 amount, bytes calldata data) external;

    function asset() external view returns (address);
}
