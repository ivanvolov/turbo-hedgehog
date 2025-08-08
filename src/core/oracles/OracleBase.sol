// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** external imports
import {TickMath} from "v4-core/libraries/TickMath.sol";

// ** libraries
import {ALMMathLib, WAD_DECIMALS} from "../../libraries/ALMMathLib.sol";

// ** interfaces
import {IOracle} from "../../interfaces/IOracle.sol";

/// @title Oracle Base
/// @notice Abstract contract that serves as a base for all oracles.
abstract contract OracleBase is IOracle {
    bool public immutable isInvertedPool;
    int256 public immutable totalDecDelta;
    uint256 public immutable scaleFactor;

    constructor(bool _isInvertedPool, int256 _totalDecDelta) {
        isInvertedPool = _isInvertedPool;
        if (_totalDecDelta < -WAD_DECIMALS) revert TotalDecimalsDeltaNotValid();

        totalDecDelta = _totalDecDelta;
        scaleFactor = 10 ** uint256(_totalDecDelta + WAD_DECIMALS);
    }

    /// @notice Calculates the price of the quote token denominated in base token units.
    /// @dev Returns the price as a 1e18 fixed-point number (UD60x18 format).
    /// @return currentPrice The price ratio as a fixed-point number with 18 decimal precision.
    function price() public view returns (uint256 currentPrice) {
        (uint256 priceBase, uint256 priceQuote) = _fetchAssetsPrices();
        currentPrice = ALMMathLib.getPrice(priceBase, priceQuote, scaleFactor);
        if (currentPrice == 0) revert PriceZero();
    }

    /// @notice Calculates both standard price and Uniswap V4 compatible sqrt price.
    /// @dev Returns the standard price as a 1e18 fixed-point number (UD60x18 format).
    /// The sqrt price is calculated as either sqrt(priceBase/priceQuote) * 2^96 or
    /// sqrt(priceQuote/priceBase) * 2^96 depending, on token ordering and pool configuration.
    /// @return currentPrice The standard price ratio (quote denominated in base token units).
    /// @return sqrtPriceX96 The square root price in Uniswap V4 Q64.96 format.
    function poolPrice() external view returns (uint256 currentPrice, uint160 sqrtPriceX96) {
        (uint256 priceBase, uint256 priceQuote) = _fetchAssetsPrices();
        currentPrice = ALMMathLib.getPrice(priceBase, priceQuote, scaleFactor);
        if (currentPrice == 0) revert PriceZero();

        sqrtPriceX96 = ALMMathLib.getSqrtPrice(priceBase, priceQuote, totalDecDelta, isInvertedPool);
        if (sqrtPriceX96 < TickMath.MIN_SQRT_PRICE || sqrtPriceX96 > TickMath.MAX_SQRT_PRICE)
            revert SqrtPriceNotValid();
    }

    function _fetchAssetsPrices() internal view virtual returns (uint256, uint256) {
        // Intentionally empty to be implemented by derived contracts.
    }
}
