// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** interfaces
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {AggregatorV3Interface as IAggV3} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {ISwapRouter} from "@v3-core/ISwapRouter.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {IEthereumVaultConnector as IEVC} from "@euler-interfaces/IEVC.sol";
import {IRewardToken as IrEUL} from "@euler-interfaces/IRewardToken.sol";
import {IMerklDistributor} from "@merkl-contracts/IMerklDistributor.sol";
import {IUniversalRewardsDistributor} from "@universal-rewards-distributor/IUniversalRewardsDistributor.sol";
import {IUniversalRouter} from "@universal-router/IUniversalRouter.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {IMorphoChainlinkOracleV2Factory} from "@morpho-oracles/IMorphoChainlinkOracleV2Factory.sol";

library Constants {
    IPoolManager constant manager = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);

    // ** ERC20 tokens
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IWETH9 constant WETH9 = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // ** Morpho
    IMorpho constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // https://app.morpho.org/ethereum/earn
    IUniversalRewardsDistributor constant universalRewardsDistributor =
        IUniversalRewardsDistributor(0x330eefa8a787552DC5cAd3C3cA644844B1E61Ddb);
    IMorphoChainlinkOracleV2Factory constant morphoOracleFactory =
        IMorphoChainlinkOracleV2Factory(0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766);

    IERC4626 constant morphoUSDTVault = IERC4626(0xbEef047a543E45807105E51A8BBEFCc5950fcfBa);
    IERC4626 constant morphoUSDCVault = IERC4626(0xd63070114470f685b75B74D60EEc7c1113d33a3D);
    IERC4626 constant morphoDAIVault = IERC4626(0x500331c9fF24D9d11aee6B07734Aa72343EA74a5);
    IERC4626 constant morphoUSDEVault = IERC4626(0x4EDfaB296F8Eb15aC0907CF9eCb7079b1679Da57);

    // ** Euler
    IEVC constant EULER_VAULT_CONNECT = IEVC(payable(0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383));
    IMerklDistributor constant merklRewardsDistributor = IMerklDistributor(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);
    IrEUL constant rEUL = IrEUL(0xf3e621395fc714B90dA337AA9108771597b4E696);

    IEulerVault constant eulerUSDCVault1 = IEulerVault(0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9); // https://app.euler.finance/?asset=USDT&network=ethereum
    IEulerVault constant eulerUSDCVault2 = IEulerVault(0xcBC9B61177444A793B85442D3a953B90f6170b7D);
    IEulerVault constant eulerUSDTVault1 = IEulerVault(0x313603FA690301b0CaeEf8069c065862f9162162);
    IEulerVault constant eulerUSDTVault2 = IEulerVault(0x7c280DBDEf569e96c7919251bD2B0edF0734C5A8);
    IEulerVault constant eulerWETHVault1 = IEulerVault(0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2);
    IEulerVault constant eulerWETHVault2 = IEulerVault(0x716bF454066a84F39A2F78b5707e79a9d64f1225);
    IEulerVault constant eulerCbBTCVault1 = IEulerVault(0x056f3a2E41d2778D3a0c0714439c53af2987718E);
    IEulerVault constant eulerCbBTCVault2 = IEulerVault(0x29A9E5A004002Ff9E960bb8BB536E076F53cbDF1);
    IEulerVault constant eulerUSDEVault = IEulerVault(0x2daCa71Cb58285212Dc05D65Cfd4f59A82BC4cF6);

    // ** Uniswap
    ISwapRouter constant UNISWAP_V3_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // https://app.uniswap.org/explore/pools/ethereum/0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36
    IUniversalRouter constant UNIVERSAL_ROUTER = IUniversalRouter(0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af);
    IPermit2 constant PERMIT_2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    address constant uniswap_v3_USDC_CBBTC_POOL = 0x4548280AC92507C9092a511C7396Cbea78FA9E49;
    address constant uniswap_v3_USDC_WETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address constant uniswap_v3_WETH_USDT_POOL = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address constant uniswap_v3_USDC_USDT_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;
    address constant uniswap_v3_DAI_USDC_POOL = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    address constant uniswap_v3_WSTETH_WETH_POOL = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;

    // ** Chainlink // https://data.chain.link/feeds/ethereum/mainnet/usdt-usd
    IAggV3 constant chainlink_feed_WETH = IAggV3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    IAggV3 constant chainlink_feed_USDC = IAggV3(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
    IAggV3 constant chainlink_feed_USDT = IAggV3(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D);
    IAggV3 constant chainlink_feed_CBBTC = IAggV3(0x2665701293fCbEB223D11A08D826563EDcCE423A);
    IAggV3 constant chainlink_feed_DAI = IAggV3(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
    IAggV3 constant zero_feed = IAggV3(address(0));

    // ** API3
    IAggV3 constant api3_feed_WETH = IAggV3(0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473);
    IAggV3 constant api3_feed_USDC = IAggV3(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f);
    IAggV3 constant api3_feed_USDT = IAggV3(0x4eadC6ee74b7Ceb09A4ad90a33eA2915fbefcf76);

    // ** API3 Sepolia
    IAggV3 constant api3_feed_USDT_sepolia = IAggV3(0x4eadC6ee74b7Ceb09A4ad90a33eA2915fbefcf76);
    IAggV3 constant api3_feed_CBBTC_sepolia = IAggV3(0xa4183Cbf2eE868dDFccd325531C4f53F737FFF68);
    IAggV3 constant api3_feed_USDC_sepolia = IAggV3(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f);
    IAggV3 constant api3_feed_DAI_sepolia = IAggV3(0x85b6dD270538325A9E0140bd6052Da4ecc18A85c);

    // ** Chronicle Sepolia
    IAggV3 constant chronicle_feed_WETH_sepolia = IAggV3(0x3b8Cd6127a6CBEB9336667A3FfCD32B3509Cb5D9);
    IAggV3 constant chronicle_feed_USDC_sepolia = IAggV3(0xb34d784dc8E7cD240Fe1F318e282dFdD13C389AC);
    IAggV3 constant chronicle_feed_USDT_sepolia = IAggV3(0x8c852EEC6ae356FeDf5d7b824E254f7d94Ac6824);
    IAggV3 constant chronicle_feed_CBBTC_sepolia = IAggV3(0xe4f05C62c09a3ec000a3f3895eFD2Ec9a1A11742);
    IAggV3 constant chronicle_feed_DAI_sepolia = IAggV3(0xaf900d10f197762794C41dac395C5b8112eD13E1);
}
