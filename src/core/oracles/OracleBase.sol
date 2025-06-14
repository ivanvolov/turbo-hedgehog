// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {PRBMathUD60x18, PRBMath} from "@prb-math/PRBMathUD60x18.sol";

// ** interfaces
import {IOracle} from "../../interfaces/IOracle.sol";

/// @title Oracle Base
/// @notice Abstract contract that serves as a base for all oracles. Holds functions to calculate price in different formats.
abstract contract OracleBase is IOracle {
    using PRBMathUD60x18 for uint256;

    bool public immutable isInvertedPool;
    uint256 public immutable ratio;
    uint256 public immutable scaleFactor;

    constructor(bool _isInvertedPool, int8 _decimalsDelta, uint256 _decimalsBase, uint256 _decimalsQuote) {
        isInvertedPool = _isInvertedPool;
        if (_decimalsDelta < -18) revert DecimalsDeltaNotValid();

        scaleFactor = 10 ** (18 + _decimalsBase - _decimalsQuote);
        ratio = 10 ** uint256(int256(_decimalsDelta) + 18);
    }

    uint256 constant WAD = 1e18;

    /// @notice Returns the price as a 1e18 fixed-point number (UD60x18)
    function price() external view returns (uint256 _price) {
        (uint256 _priceBase, uint256 _priceQuote) = _fetchAssetsPrices();

        _price = PRBMath.mulDiv(uint256(_priceQuote), scaleFactor, uint256(_priceBase)).mul(ratio);
        if (_price == 0) revert PriceZero();
    }

    //TODO: add comment here
    function poolPrice() external view returns (uint256 _price, uint256 _poolPrice) {
        (uint256 _priceBase, uint256 _priceQuote) = _fetchAssetsPrices();

        //TODO: jum this functions into one if possible
        _price = PRBMath.mulDiv(uint256(_priceQuote), scaleFactor, uint256(_priceBase));
        _poolPrice = isInvertedPool ? WAD.div(_price.mul(ratio)) : _price.mul(ratio);
        _price = _price.mul(ratio);

        if (_price == 0 || _poolPrice == 0) revert PriceZero();
    }

    function _fetchAssetsPrices() internal view virtual returns (uint256, uint256) {}
}
