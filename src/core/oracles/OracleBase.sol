// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {PRBMathUD60x18, PRBMath} from "@prb-math/PRBMathUD60x18.sol";

// ** libraries
import {ALMMathLib} from "../../libraries/ALMMathLib.sol";

// ** interfaces
import {IOracle} from "../../interfaces/IOracle.sol";

abstract contract OracleBase is IOracle {
    using PRBMathUD60x18 for uint256;

    bool public immutable isInvertedPool;
    uint8 public immutable decimalsQuote;
    uint8 public immutable decimalsBase;

    uint8 public immutable bDec;
    uint8 public immutable qDec;

    constructor(bool _isInvertedPool, uint8 _bDec, uint8 _qDec) {
        isInvertedPool = _isInvertedPool;
        bDec = _bDec;
        qDec = _qDec;
    }

    /// @notice Returns the price as a 1e18 fixed-point number (UD60x18)
    function price() external view returns (uint256 _price) {
        (uint256 _priceQuote, uint256 _priceBase) = _fetchAssetsPrices();

        uint256 scaleFactor = 18 + decimalsBase - decimalsQuote;
        _price = PRBMath.mulDiv(uint256(_priceQuote), 10 ** scaleFactor, uint256(_priceBase));
        require(_price > 0, "O4");
    }

    uint256 constant WAD = 1e18;
    function poolPrice() external view returns (uint256 _price, uint256 _poolPrice) {
        (uint256 _priceQuote, uint256 _priceBase) = _fetchAssetsPrices();

        uint256 scaleFactor = 18 + decimalsBase - decimalsQuote;
        _price = PRBMath.mulDiv(uint256(_priceQuote), 10 ** scaleFactor, uint256(_priceBase));

        {
            uint256 decimalsDelta = uint8(ALMMathLib.absSub(bDec, qDec));
            uint256 ratio = WAD * (10 ** decimalsDelta); // @Notice: 1e12/p, 1e30 is 1e12 with 18 decimals
            if (isInvertedPool) _poolPrice = ratio.div(_price);
            else _poolPrice = _price.div(ratio);
        }

        require(_price > 0, "O4");
        require(_poolPrice > 0, "O5");
    }

    function _fetchAssetsPrices() internal view virtual returns (uint256, uint256) {}
}
