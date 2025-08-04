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
    int256 public immutable totalDecimalsDelta;
    uint256 public immutable scaleFactor;

    constructor(bool _isInvertedPool, int256 _totalDecimalsDelta) {
        isInvertedPool = _isInvertedPool;
        if (_totalDecimalsDelta < -18) revert TotalDecimalsDeltaNotValid();

        totalDecimalsDelta = _totalDecimalsDelta;
        scaleFactor = 10 ** uint256(_totalDecimalsDelta + 18);
    }

    /// @notice Returns the price as a 1e18 fixed-point number (UD60x18).
    /// Calculates quote token price in terms of base token, adjusted for token decimals.
    /// @return _price The price of quote token denominated in base token units.
    function price() public view returns (uint256 _price) {
        (uint256 _priceBase, uint256 _priceQuote) = _fetchAssetsPrices();
        _price = mulDiv(_priceQuote, scaleFactor, _priceBase);
        if (_price == 0) revert PriceZero();
    }

    /// @notice Returns both standard price and Uniswap V4 style pool price.
    /// Pool price is inverted (1/price) if token0 eq base and token1 eq quote.
    /// @return _price The standard price (quote in terms of base).
    /// @return _sqrtPriceX96 The Uniswap V4 pool-compatible sqrt price.
    function poolPrice() external view returns (uint256 _price, uint160 _sqrtPriceX96) {
        (uint256 _priceBase, uint256 _priceQuote) = _fetchAssetsPrices();
        _price = mulDiv(_priceQuote, scaleFactor, _priceBase);
        if (_price == 0) revert PriceZero();

        if (totalDecimalsDelta < 0) {
            _priceBase = _priceBase * 10 ** uint256(-totalDecimalsDelta);
        } else if (totalDecimalsDelta > 0) {
            _priceQuote = _priceQuote * 10 ** uint256(totalDecimalsDelta);
        }
        bool invert = _priceBase <= _priceQuote;
        (uint256 lowP, uint256 highP) = invert ? (_priceBase, _priceQuote) : (_priceQuote, _priceBase);
        uint256 res = mulDiv(lowP, type(uint256).max, highP);
        res = sqrt(res);
        if (invert != isInvertedPool) res = type(uint256).max / res;
        res = res >> 32;
        _sqrtPriceX96 = SafeCast.toUint160(res);

        if (_sqrtPriceX96 < TickMath.MIN_SQRT_PRICE || _sqrtPriceX96 > TickMath.MAX_SQRT_PRICE)
            revert SqrtPriceNotValid();
    }

    function _fetchAssetsPrices() internal view virtual returns (uint256, uint256) {}
}
