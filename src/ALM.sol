// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** external imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ** contracts
import {Base} from "./core/base/Base.sol";

// ** libraries
import {ALMMathLib} from "./libraries/ALMMathLib.sol";

// ** interfaces
import {IALM} from "./interfaces/IALM.sol";

/// @title Automated Liquidity Manager
/// @author Ivan Volovyk <https://github.com/ivanvolov>
/// @custom:contact ivan@lumis.fi
/// @notice The main contract that handles the deposit and withdrawal flow.
contract ALM is Base, ERC20, ReentrancyGuard, IALM {
    using SafeERC20 for IERC20;

    /// @notice Current operational status of the contract.
    /// @dev 0 = active, 1 = paused, 2 = shutdown.
    uint8 public status = 0;
    uint256 public tvlCap;
    bool public immutable isInvertedAssets;
    address public liquidityOperator;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        bool _isInvertedAssets,
        string memory name,
        string memory symbol
    ) Base(ComponentType.ALM, msg.sender, _base, _quote) ERC20(name, symbol) {
        isInvertedAssets = _isInvertedAssets;
    }

    function setStatus(uint8 _status) external onlyOwner {
        status = _status;
        emit StatusSet(_status);
    }

    function setOperator(address _liquidityOperator) external onlyOwner {
        liquidityOperator = _liquidityOperator;
        emit OperatorSet(_liquidityOperator);
    }

    function setTVLCap(uint256 _tvlCap) external onlyOwner {
        tvlCap = _tvlCap;
        emit TVLCapSet(_tvlCap);
    }

    function deposit(
        address to,
        uint256 amountIn,
        uint256 minShares
    ) external onlyActive nonReentrant returns (uint256 sharesMinted) {
        if (liquidityOperator != address(0) && liquidityOperator != msg.sender) revert NotALiquidityOperator();
        if (amountIn == 0) revert ZeroLiquidity();
        lendingAdapter.syncPositions();
        uint256 price = oracle.price();
        uint256 tvlBefore = TVL(price);

        if (isInvertedAssets) {
            BASE.safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralShort(getBalanceBase());
        } else {
            QUOTE.safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralLong(getBalanceQuote());
        }
        uint256 tvlAfter = TVL(price);
        if (tvlAfter > tvlCap) revert TVLCapExceeded();

        sharesMinted = ALMMathLib.getSharesToMint(tvlBefore, tvlAfter, totalSupply());
        if (sharesMinted < minShares) revert NotMinShares();
        _mint(to, sharesMinted);
        emit Deposit(to, amountIn, sharesMinted, tvlAfter, totalSupply());
    }

    function withdraw(
        address to,
        uint256 sharesOut,
        uint256 minAmountOutB,
        uint256 minAmountOutQ
    ) external notPaused nonReentrant {
        if (liquidityOperator != address(0) && liquidityOperator != msg.sender) revert NotALiquidityOperator();
        if (sharesOut == 0) revert NotZeroShares();
        lendingAdapter.syncPositions();

        (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();
        (uint256 uCL, uint256 uCS, uint256 uDL, uint256 uDS) = ALMMathLib.getUserAmounts(
            totalSupply(),
            sharesOut,
            CL,
            CS,
            DL,
            DS
        );

        _burn(msg.sender, sharesOut);
        if (uDS != 0 && uDL != 0) flashLoanAdapter.flashLoanTwoTokens(uDL, uDS, abi.encode(uCL, uCS));
        else if (uDS == 0 && uDL == 0) {
            if (uCL != 0 && uCS != 0)
                lendingAdapter.updatePosition(SafeCast.toInt256(uCL), SafeCast.toInt256(uCS), 0, 0);
            else if (uCL != 0) lendingAdapter.removeCollateralLong(uCL);
            else if (uCS != 0) lendingAdapter.removeCollateralShort(uCS);

            if (isInvertedAssets) swapAdapter.swapExactInput(false, getBalanceQuote());
            else swapAdapter.swapExactInput(true, getBalanceBase());
        } else if (uDL > 0) flashLoanAdapter.flashLoanSingle(true, uDL, abi.encode(uCL, uCS));
        else revert NotAValidPositionState();

        uint256 baseOut;
        uint256 quoteOut;
        if (isInvertedAssets) {
            baseOut = getBalanceBase();
            if (baseOut < minAmountOutB) revert NotMinOutWithdrawBase();
            BASE.safeTransfer(to, baseOut);
        } else {
            quoteOut = getBalanceQuote();
            if (quoteOut < minAmountOutQ) revert NotMinOutWithdrawQuote();
            QUOTE.safeTransfer(to, quoteOut);
        }

        uint128 newLiquidity = hook.updateLiquidity();
        emit Withdraw(to, sharesOut, baseOut, quoteOut, totalSupply(), newLiquidity);
    }

    function onFlashLoanTwoTokens(
        uint256 amountBase,
        uint256 amountQuote,
        bytes calldata data
    ) external notPaused onlyFlashLoanAdapter {
        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));
        lendingAdapter.updatePosition(
            SafeCast.toInt256(uCL),
            SafeCast.toInt256(uCS),
            -SafeCast.toInt256(amountBase),
            -SafeCast.toInt256(amountQuote)
        );
        if (isInvertedAssets) ensureEnoughBalance(amountQuote, QUOTE);
        else ensureEnoughBalance(amountBase, BASE);
    }

    function onFlashLoanSingle(
        bool isBase,
        uint256 amount,
        bytes calldata data
    ) external notPaused onlyFlashLoanAdapter {
        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));

        (int256 deltaDL, int256 deltaDS) = isBase
            ? (-SafeCast.toInt256(amount), int256(0))
            : (int256(0), -SafeCast.toInt256(amount));
        lendingAdapter.updatePosition(SafeCast.toInt256(uCL), SafeCast.toInt256(uCS), deltaDL, deltaDS);

        if (isBase) {
            if (isInvertedAssets) swapAdapter.swapExactInput(false, getBalanceQuote());
            else ensureEnoughBalance(amount, BASE);
        } else {
            if (isInvertedAssets) ensureEnoughBalance(amount, QUOTE);
            else swapAdapter.swapExactInput(true, getBalanceBase());
        }
    }

    function ensureEnoughBalance(uint256 targetBalance, IERC20 token) internal {
        uint256 balance = token == BASE ? getBalanceBase() : getBalanceQuote();
        if (targetBalance >= balance) swapAdapter.swapExactOutput(token == QUOTE, targetBalance - balance);
        else swapAdapter.swapExactInput(token == BASE, balance - targetBalance);
    }

    // ** Math functions

    function TVL(uint256 price) public view returns (uint256) {
        (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();
        return ALMMathLib.getTVL(getBalanceQuote(), getBalanceBase(), CL, CS, DL, DS, price, isInvertedAssets);
    }

    // ** Helpers

    function getBalanceBase() internal view returns (uint256) {
        return BASE.balanceOf(address(this));
    }

    function getBalanceQuote() internal view returns (uint256) {
        return QUOTE.balanceOf(address(this));
    }
}
