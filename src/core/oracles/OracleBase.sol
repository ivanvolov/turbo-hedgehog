// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {PRBMathUD60x18, PRBMath} from "@prb-math/PRBMathUD60x18.sol";

// ** interfaces
import {IOracle} from "../../interfaces/IOracle.sol";

abstract contract OracleBase is IOracle {
    using PRBMathUD60x18 for uint256;

    bool public immutable isInvertedPool;
    uint256 public immutable ratio;
    uint256 public immutable scaleFactor;

    constructor(bool _isInvertedPool, int8 _decimalsDelta, uint256 _decimalsBase, uint256 _decimalsQuote) {
        isInvertedPool = _isInvertedPool;
        if (_decimalsDelta < -18) revert("O1");

        scaleFactor = 10 ** (18 + _decimalsBase - _decimalsQuote);
        ratio = 10 ** uint256(int256(_decimalsDelta) + 18);
    }

    /// @notice Returns the price as a 1e18 fixed-point number (UD60x18)
    function price() external view returns (uint256 _price) {
        (uint256 _priceBase, uint256 _priceQuote) = _fetchAssetsPrices();

        _price = PRBMath.mulDiv(uint256(_priceQuote), scaleFactor, uint256(_priceBase));
        require(_price > 0, "O2");
    }

    //TODO: only use test_price in the future
    /// @notice Returns the price as a 1e18 fixed-point number (UD60x18)
    function test_price() external view returns (uint256 _price) {
        (uint256 _priceBase, uint256 _priceQuote) = _fetchAssetsPrices();

        _price = PRBMath.mulDiv(uint256(_priceQuote), scaleFactor, uint256(_priceBase));
        _price = _price.mul(ratio); // TODO: it either always this or depends on isInvertPool
    }

    /// @notice Returns the price as a 1e18 fixed-point number (UD60x18)
    function test_price() external view returns (uint256 _price) {
        (uint256 _priceQuote, uint256 _priceBase) = _fetchAssetsPrices();

        uint256 scaleFactor = 18 + decimalsBase - decimalsQuote;
        _price = PRBMath.mulDiv(uint256(_priceQuote), 10 ** scaleFactor, uint256(_priceBase));

        {
            uint256 decimalsDelta = uint8(ALMMathLib.absSub(bDec, qDec));
            uint256 ratio = WAD * (10 ** decimalsDelta); // @Notice: 1e12/p, 1e30 is 1e12 with 18 decimals
            // _price = ratio.div(_price);
            _price = _price.div(ratio); // TODO: it either always this or depends on isInvertPool
        }
    }

    uint256 constant WAD = 1e18;
    //TODO: add comment here
    function poolPrice() external view returns (uint256 _price, uint256 _poolPrice) {
        (uint256 _priceBase, uint256 _priceQuote) = _fetchAssetsPrices();

        //TODO: jum this functions into one if possible
        _price = PRBMath.mulDiv(uint256(_priceQuote), scaleFactor, uint256(_priceBase));
        _poolPrice = isInvertedPool ? WAD.div(_price.mul(ratio)) : _price.mul(ratio);

        require(_price > 0, "O2");
        require(_poolPrice > 0, "O3");
    }

    function _fetchAssetsPrices() internal view virtual returns (uint256, uint256) {}
}
