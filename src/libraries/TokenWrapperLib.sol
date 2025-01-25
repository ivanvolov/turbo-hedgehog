// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

//TODO: leverage this to make it stronger https://github.com/dl-solarity/solidity-lib/blob/master/contracts/libs/utils/DecimalsConverter.sol

library TokenWrapperLib {
    uint8 internal constant WAD = 18;

    function wrap(uint256 a, uint8 tokenWAD) internal pure returns (uint256) {
        if (tokenWAD == WAD) return a;
        else if (tokenWAD > WAD) return a / 10 ** (tokenWAD - 18);
        else return a * 10 ** (18 - tokenWAD);
    }

    function unwrap(uint256 a, uint8 tokenWAD) internal pure returns (uint256) {
        if (tokenWAD == WAD) return a;
        else if (tokenWAD > WAD) return a * 10 ** (tokenWAD - 18);
        else return a / 10 ** (18 - tokenWAD);
    }
}
