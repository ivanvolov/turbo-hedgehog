// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library TokenWrapperLib {
    uint8 internal constant WAD_DECIMALS = 18;

    function wrap(uint256 a, uint8 tokenDecimals) internal pure returns (uint256) {
        if (tokenDecimals == WAD_DECIMALS) return a;
        else if (tokenDecimals > WAD_DECIMALS) return a / 10 ** (tokenDecimals - WAD_DECIMALS);
        else return a * 10 ** (WAD_DECIMALS - tokenDecimals);
    }

    function unwrap(uint256 a, uint8 tokenDecimals) internal pure returns (uint256) {
        if (tokenDecimals == WAD_DECIMALS) return a;
        else if (tokenDecimals > WAD_DECIMALS) return a * 10 ** (tokenDecimals - WAD_DECIMALS);
        else return a / 10 ** (WAD_DECIMALS - tokenDecimals);
    }
}
