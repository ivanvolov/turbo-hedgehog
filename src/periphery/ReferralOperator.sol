// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

// ** interfaces
import {IALM} from "../interfaces/IALM.sol";

contract ReferralOperatorMock is Ownable {
    error NotAuthorized();
    error NotEnoughRewards();

    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;

    IALM public immutable alm;
    IERC20 public immutable token;

    struct ReferralInfo {
        address user;
        uint256 amountIn;
        uint256 shares;
        address referral;
        uint256 performanceFee;
    }

    mapping(address => uint256) public referralRewards;
    mapping(uint256 => ReferralInfo) public referralInfo;
    uint256 public nextReferralId;

    constructor(IALM _alm, IERC20 _token) Ownable(msg.sender) {
        alm = _alm;
        token = _token;
        token.forceApprove(address(_alm), type(uint256).max);
    }

    function redeemReferralRewards(address to, uint256 amount) external returns (uint256 rewardsOut) {
        if (referralRewards[msg.sender] < amount) revert NotEnoughRewards();
        referralRewards[msg.sender] -= amount;
        token.safeTransfer(to, amount);
    }

    function deposit(
        address to,
        uint256 amountIn,
        uint256 minShares,
        address referral,
        uint256 performanceFee
    ) external returns (uint256 sharesMinted, uint256 positionId) {
        token.safeTransferFrom(msg.sender, address(this), amountIn);
        sharesMinted = alm.deposit(address(this), amountIn, minShares);

        referralInfo[nextReferralId] = ReferralInfo({
            user: to,
            amountIn: amountIn,
            referral: referral,
            shares: sharesMinted,
            performanceFee: performanceFee
        });
        positionId = nextReferralId;
        nextReferralId++;
    }

    /// @notice Withdraws funds from a position and handles referral rewards
    /// @param positionId The ID of the position to withdraw from
    /// @param to The address to receive the withdrawn funds
    /// @param minAmountOutB Minimum amount of base token to receive
    /// @param minAmountOutQ Minimum amount of quote token to receive
    function withdraw(
        uint256 positionId,
        address to,
        uint256 minAmountOutB,
        uint256 minAmountOutQ
    ) external returns (uint256 amountOut) {
        ReferralInfo memory refInfo = referralInfo[positionId];
        if (refInfo.user != msg.sender) revert NotAuthorized();

        (uint256 baseOut, uint256 quoteOut) = alm.withdraw(address(this), refInfo.shares, minAmountOutB, minAmountOutQ);
        unchecked {
            amountOut = baseOut + quoteOut; /// @dev One of baseOut or quoteOut is always zero, so using addition is cheaper than min(baseOut, quoteOut)
        }

        if (amountOut > refInfo.amountIn) {
            uint256 referralFee = (amountOut - refInfo.amountIn).mul(refInfo.performanceFee);
            referralRewards[refInfo.referral] += referralFee;
            amountOut -= referralFee;
        }

        delete referralInfo[positionId];
        token.safeTransfer(to, amountOut);
    }
}
