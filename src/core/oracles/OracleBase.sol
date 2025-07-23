// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UD60x18, ud} from "@prb-math/UD60x18.sol";
import {mulDiv} from "@prb-math/Common.sol";

// ** interfaces
import {IOracle} from "../../interfaces/IOracle.sol";

/// @title Oracle Base
/// @notice Abstract contract that serves as a base for all oracles. Holds functions to calculate price in different formats.
abstract contract OracleBase is Ownable, IOracle {
    bool public immutable isInvertedPool;
    UD60x18 public immutable ratio;
    uint256 public immutable scaleFactor;
    StalenessThresholds public stalenessThresholds;

    constructor(bool _isInvertedPool, int8 tokenDecimalsDelta, int8 feedDecimalsDelta) Ownable(msg.sender) {
        isInvertedPool = _isInvertedPool;
        if (tokenDecimalsDelta < -18) revert TokenDecimalsDeltaNotValid();
        if (feedDecimalsDelta < -18) revert FeedDecimalsDeltaNotValid();

        ratio = ud(10 ** uint256(int256(tokenDecimalsDelta) + 18));
        scaleFactor = 10 ** uint256(int256(feedDecimalsDelta) + 18);
    }

    function setStalenessThresholds(uint128 thresholdBase, uint128 thresholdQuote) external override onlyOwner {
        stalenessThresholds = StalenessThresholds(thresholdBase, thresholdQuote);
        emit StalenessThresholdsSet(thresholdBase, thresholdQuote);
    }

    UD60x18 constant WAD = UD60x18.wrap(1e18);

    /// @notice Returns the price as a 1e18 fixed-point number (UD60x18).
    /// Calculates quote token price in terms of base token, adjusted for token decimals.
    /// @return _price The price of quote token denominated in base token units.
    function price() public view returns (uint256 _price) {
        (uint256 _priceBase, uint256 _priceQuote) = _fetchAssetsPrices();

        _price = ud(mulDiv(_priceQuote, scaleFactor, _priceBase)).mul(ratio).unwrap();
        if (_price == 0) revert PriceZero();
    }

    /// @notice Returns both standard price and Uniswap V3 style pool price.
    /// Pool price is inverted (1/price) if token0 eq base and token1 eq quote.
    /// @return _price The standard price (quote in terms of base).
    /// @return _poolPrice The pool-compatible price.
    function poolPrice() external view returns (uint256 _price, uint256 _poolPrice) {
        _price = price();
        _poolPrice = isInvertedPool ? WAD.div(ud(_price)).unwrap() : _price;
        if (_poolPrice == 0) revert PriceZero();
    }

    function _fetchAssetsPrices() internal view virtual returns (uint256, uint256) {}
}
