// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IOracleTest, IChronicleSelfKisser} from "@test/interfaces/IOracleTest.sol";

contract OracleFuzzing is ALMTestBase {
    function setUp() public {
        _select_mainnet_fork(23059745);
    }
    // ** Fuzzers

    /// @notice Chronicle feeds are always 18. Api3 always have 18 decimals. https://docs.api3.org/dapps/integration/contract-integration.html#using-value.
    ///         Chainlink feeds are 8 for USDT, USDC, DAI, ETH, BTC, WBTC, CBBTC, WSTETH.
    ///         So the feedBDec - feedQDec = 0 in these cases.

    /// @dev Tests WSTETH-WETH and ETH-WSTETH with one feed.
    function test_Fuzz_WSTETH_ETH_Chronicle_Api3_Chainlink(uint256 priceWSTETH) public view {
        uint256 quote_MIN = 5e17; // 0.5ETH for WSTETH.
        uint256 quote_MAX = 100e18; //  1000ETH USDT.
        priceWSTETH = bound(priceWSTETH, quote_MIN, quote_MAX);

        // We will construct totalDecDel = 0 in one feed oracle.
        TestLib.newOracleGetPrices(priceWSTETH, 1e18, int256(0), true);
        TestLib.newOracleGetPrices(1e18, priceWSTETH, int256(0), true);
    }

    /// @dev Tests ETH/USDC, USDC/ETH, ETH/USDT, USDT/ETH for for both V4 and V3 oracles (with native and not).
    function test_Fuzz_ETH_USDC_T_Chronicle_Api3_Chainlink(uint256 priceUSD, uint256 priceETH) public view {
        uint256 base_MIN = 1e17; // 0.1$ for USDC/T.
        uint256 base_MAX = 100e18; //  100$ for USDC/T.
        uint256 quote_MIN = 1e17; // 0.1$ for ETH/WETH.
        uint256 quote_MAX = 10 * 10e6 * 1e18; //  10kk ETH/WETH.
        priceUSD = bound(priceUSD, base_MIN, base_MAX);
        priceETH = bound(priceETH, quote_MIN, quote_MAX);

        // Chronicle and API3 feeds are always 18. So 18-18 = 0. The chainlink have 8 on these examples.
        int256 totalDecDel = int8(6 - 18);
        TestLib.newOracleGetPrices(priceUSD, priceETH, totalDecDel, false);
        TestLib.newOracleGetPrices(priceUSD, priceETH, totalDecDel, true);
        TestLib.newOracleGetPrices(priceETH, priceUSD, -totalDecDel, true);
        TestLib.newOracleGetPrices(priceETH, priceUSD, -totalDecDel, false);
    }

    /// @dev Tests USDT/CBBTC, CBBTC/USDT, USDC/CBBTC, CBBTC/USDC,
    ///      USDT/WBTC, WBTC/USDT, USDC/WBTC, WBTC/USDC.
    function test_Fuzz_BTC_USD_Chronicle_Api3_Chainlink(uint256 priceUSD, uint256 priceBTC) public view {
        uint256 base_MIN = 1e17; // 0.1$ for USDT/C.
        uint256 base_MAX = 100e18; //  100$ for USDT/C.
        uint256 quote_MIN = 1e17; // 0.1$ for CBBTC/WBTC.
        uint256 quote_MAX = 100 * 10e6 * 1e18; //  100kk CBBTC.
        priceUSD = bound(priceUSD, base_MIN, base_MAX);
        priceBTC = bound(priceBTC, quote_MIN, quote_MAX);

        // Chronicle and API3 feeds are always 18. So 18-18 = 0. The chainlink have 8 on these examples.
        int256 totalDecDel = int8(8 - 6);
        TestLib.newOracleGetPrices(priceBTC, priceUSD, totalDecDel, false);
        TestLib.newOracleGetPrices(priceBTC, priceUSD, totalDecDel, true); // just in case.
        TestLib.newOracleGetPrices(priceUSD, priceBTC, -totalDecDel, true);
        TestLib.newOracleGetPrices(priceUSD, priceBTC, -totalDecDel, false); // just in case.
    }

    /// @dev Tests USDC/DAI, DAI/USDC, USDT/DAI, DAI/USDT.
    function test_Fuzz_DAI_USDC_T_Chronicle_Api3_Chainlink(uint256 priceUSD, uint256 priceDAI) public view {
        uint256 base_MIN = 1e17; // 0.1$ for USDT/C.
        uint256 base_MAX = 100e18; //  100$ for USDT/C.
        uint256 quote_MIN = 1e17; // 0.1$ for DAI.
        uint256 quote_MAX = 100e18; //  100$ DAI.
        priceUSD = bound(priceUSD, base_MIN, base_MAX);
        priceDAI = bound(priceDAI, quote_MIN, quote_MAX);

        // Chronicle and API3 feeds are always 18. So 18-18 = 0. The chainlink have 8 on these examples.
        int256 totalDecDel = int8(18 - 6);
        TestLib.newOracleGetPrices(priceDAI, priceUSD, totalDecDel, true);
        TestLib.newOracleGetPrices(priceDAI, priceUSD, totalDecDel, false); // just in case.
        TestLib.newOracleGetPrices(priceUSD, priceDAI, -totalDecDel, false);
        TestLib.newOracleGetPrices(priceUSD, priceDAI, -totalDecDel, true); // just in case.
    }

    /// @dev Tests USDC/USDT, USDT/USDC.
    function test_Fuzz_USDT_USDC_Chronicle_Api3_Chainlink(uint256 priceUSDC, uint256 priceUSDT) public view {
        uint256 base_MIN = 1e17; // 0.1$ for USDC.
        uint256 base_MAX = 100e18; //  100$ for USDC.
        uint256 quote_MIN = 1e17; // 0.1$ for USDT.
        uint256 quote_MAX = 100e18; //  100$ USDT.
        priceUSDC = bound(priceUSDC, base_MIN, base_MAX);
        priceUSDT = bound(priceUSDT, quote_MIN, quote_MAX);

        // Chronicle and API3 feeds are always 18. So 18-18 = 0. The chainlink have 8 on these examples.
        int256 totalDecDel = int8(6 - 6);
        TestLib.newOracleGetPrices(priceUSDT, priceUSDC, totalDecDel, false);
        TestLib.newOracleGetPrices(priceUSDC, priceUSDT, totalDecDel, true);
    }

    // ** Helpers

    function _select_mainnet_fork(uint256 block_number) internal {
        select_mainnet_fork(block_number);
        _create_accounts();
        manager = MConstants.manager;
    }
}
