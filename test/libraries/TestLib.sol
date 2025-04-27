// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// ** libraries
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ABDKMath64x64} from "@test/libraries/ABDKMath64x64.sol";

library TestLib {

    uint256 constant startBlock = 22359025;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    // ** https://app.morpho.org/ethereum/earn
    address constant morphoUSDTVault = 0xbEef047a543E45807105E51A8BBEFCc5950fcfBa;
    address constant morphoUSDCVault = 0xd63070114470f685b75B74D60EEc7c1113d33a3D;
    address constant morphoDAIVault = 0x500331c9fF24D9d11aee6B07734Aa72343EA74a5;
    address constant morphoUSDEVault = 0x4EDfaB296F8Eb15aC0907CF9eCb7079b1679Da57;

    // ** https://app.euler.finance/?asset=USDT&network=ethereum
    address constant eulerUSDCVault1 = 0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9;
    address constant eulerUSDCVault2 = 0xcBC9B61177444A793B85442D3a953B90f6170b7D;
    address constant eulerUSDTVault1 = 0x313603FA690301b0CaeEf8069c065862f9162162;
    address constant eulerUSDTVault2 = 0x7c280DBDEf569e96c7919251bD2B0edF0734C5A8;
    address constant eulerWETHVault1 = 0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2;
    address constant eulerWETHVault2 = 0x716bF454066a84F39A2F78b5707e79a9d64f1225;
    address constant eulerCbBTCVault1 = 0x056f3a2E41d2778D3a0c0714439c53af2987718E;
    address constant eulerCbBTCVault2 = 0x29A9E5A004002Ff9E960bb8BB536E076F53cbDF1;
    address constant eulerUSDEVault = 0x2daCa71Cb58285212Dc05D65Cfd4f59A82BC4cF6;

    // ** https://app.uniswap.org/explore/pools/ethereum/0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36
    address constant uniswap_v3_cbBTC_USDC_POOL = 0x4548280AC92507C9092a511C7396Cbea78FA9E49;
    address constant uniswap_v3_WETH_USDC_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant uniswap_v3_WETH_USDT_POOL = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address constant uniswap_v3_USDC_USDT_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;
    address constant uniswap_v3_DAI_USDC_POOL = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    address constant uniswap_v3_USDE_USDT_POOL = 0x435664008F38B0650fBC1C9fc971D0A3Bc2f1e47;

    // ** https://data.chain.link/feeds/ethereum/mainnet/usdt-usd
    address constant chainlink_feed_WETH = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant chainlink_feed_USDC = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant chainlink_feed_USDT = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address constant chainlink_feed_cbBTC = 0x2665701293fCbEB223D11A08D826563EDcCE423A;
    address constant chainlink_feed_DAI = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address constant chainlink_feed_USDE = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;

    uint256 constant sqrt_price_10per_price_change = 48808848170151600; //(sqrt(1.1)-1) or max 10% price change

    function nearestUsableTick(int24 tick_, uint24 tickSpacing) public pure returns (int24 result) {
        result = int24(divRound(int128(tick_), int128(int24(tickSpacing)))) * int24(tickSpacing);

        if (result < TickMath.MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > TickMath.MAX_TICK) {
            result -= int24(tickSpacing);
        }
    }

    function divRound(int128 x, int128 y) internal pure returns (int128 result) {
        int128 quot = ABDKMath64x64.div(x, y);
        result = quot >> 64;

        // Check if remainder is greater than 0.5
        if (quot % 2 ** 64 >= 0x8000000000000000) {
            result += 1;
        }
    }

    function getTickSpacingFromFee(uint24 fee) public pure returns (int24) {
        return int24((fee / 100) * 2);
    }
}
