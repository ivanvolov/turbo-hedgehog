// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {mulDiv, mulDiv18 as mul18, sqrt} from "@prb-math/Common.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// ** libraries
import {ALMMathLib} from "../../libraries/ALMMathLib.sol";

// ** interfaces
import {IOracle} from "../../interfaces/IOracle.sol";

/// @title Oracle Base
/// @notice Abstract contract that serves as a base for all oracles. Holds functions to calculate price in different formats.
abstract contract OracleBase is IOracle {
    bool public immutable isInvertedPool;
    int256 public immutable totalDecDelta;
    uint256 public immutable scaleFactor;

    constructor(bool _isInvertedPool, int256 _totalDecDelta) {
        isInvertedPool = _isInvertedPool;
        if (_totalDecDelta < -18) revert TotalDecimalsDeltaNotValid();

        totalDecDelta = _totalDecDelta;
        scaleFactor = 10 ** uint256(_totalDecDelta + 18);
    }

    /// @notice Calculates the price of the quote token denominated in base token units.
    /// @dev Returns the price as a 1e18 fixed-point number (UD60x18 format).
    /// @return price The price ratio as a fixed-point number with 18 decimal precision.
    function price() public view returns (uint256 price) {
        (uint256 priceBase, uint256 priceQuote) = _fetchAssetsPrices();
        price = mulDiv(priceQuote, scaleFactor, priceBase);
        if (price == 0) revert PriceZero();
    }

    /// @notice Calculates both standard price and Uniswap V4 compatible sqrt price.
    /// @dev Returns the standard price as a 1e18 fixed-point number (UD60x18 format).
    /// The sqrt price is calculated as either sqrt(priceBase/priceQuote) * 2^96 or
    /// sqrt(priceQuote/priceBase) * 2^96 depending on token ordering and pool configuration.
    /// @return price The standard price ratio (quote denominated in base token units).
    /// @return sqrtPriceX96 The square root price in Uniswap V4 Q64.96 format.
    function poolPrice() external view returns (uint256 price, uint160 sqrtPriceX96) {
        (uint256 priceBase, uint256 priceQuote) = _fetchAssetsPrices();
        price = mulDiv(priceQuote, scaleFactor, priceBase);
        if (price == 0) revert PriceZero();

        if (totalDecDelta < 0) {
            priceBase = priceBase * 10 ** uint256(-totalDecDelta);
        } else if (totalDecDelta > 0) {
            priceQuote = priceQuote * 10 ** uint256(totalDecDelta);
        }
        bool invert = priceBase <= priceQuote;
        (uint256 lowP, uint256 highP) = invert ? (priceBase, priceQuote) : (priceQuote, priceBase);
        uint256 res = mulDiv(lowP, type(uint256).max, highP);
        res = sqrt(res);
        if (invert != isInvertedPool) res = type(uint256).max / res;
        res = res >> 32;
        sqrtPriceX96 = SafeCast.toUint160(res);

        if (sqrtPriceX96 < TickMath.MIN_SQRT_PRICE || sqrtPriceX96 > TickMath.MAX_SQRT_PRICE)
            revert SqrtPriceNotValid();
    }

    function _fetchAssetsPrices() internal view virtual returns (uint256, uint256) {}
}
