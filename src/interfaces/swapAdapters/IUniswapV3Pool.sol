// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3Pool {
    function fee() external view returns (uint24);

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}
