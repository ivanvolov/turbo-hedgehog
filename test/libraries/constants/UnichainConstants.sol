// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// forge-lint: disable-start(screaming-snake-case-const)

// ** interfaces
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {AggregatorV3Interface as IAggV3} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {IEthereumVaultConnector as IEVC} from "@euler-interfaces/IEVC.sol";
import {IRewardToken as IrEUL} from "@euler-interfaces/IRewardToken.sol";
import {IMerklDistributor} from "@merkl-contracts/IMerklDistributor.sol";
import {IUniversalRouter} from "@universal-router/IUniversalRouter.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";

library Constants {
    IPoolManager constant manager = IPoolManager(0x1F98400000000000000000000000000000000004);

    // ** ERC20 tokens
    address constant WETH = 0x4200000000000000000000000000000000000006; // https://docs.unichain.org/docs/technical-information/contract-addresses
    IWETH9 constant WETH9 = IWETH9(0x4200000000000000000000000000000000000006);
    address constant USDC = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;
    address constant USDT = 0x9151434b16b9763660705744891fA906F660EcC5;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c; // Official
    // address constant WBTC = 0x927B51f251480a681271180DA4de28D44EC4AfB8; // Bridged - only used by Morpho.
    address constant DAI = 0x20CAb320A855b39F724131C69424240519573f81;
    address constant WSTETH = 0xc02fE7317D4eb8753a02c35fe019786854A92001;

    // ** Morpho
    IMorpho constant MORPHO = IMorpho(0x8f5ae9CddB9f68de460C77730b018Ae7E04a140A); // https://docs.morpho.org/getting-started/resources/addresses/
    IERC4626 constant morphoUSDCVault = IERC4626(0x38f4f3B6533de0023b9DCd04b02F93d36ad1F9f9); // https://app.morpho.org/unichain/vault/0x38f4f3B6533de0023b9DCd04b02F93d36ad1F9f9/gauntlet-usdc
    IERC4626 constant morphoUSDTVault = IERC4626(0x89849B6e57e1c61e447257242bDa97c70FA99b6b); // Gauntlet

    // ** Euler
    IEVC constant EULER_VAULT_CONNECT = IEVC(payable(0x2A1176964F5D7caE5406B627Bf6166664FE83c60)); // https://github.com/euler-xyz/euler-interfaces/tree/master/addresses/130
    IMerklDistributor constant merklRewardsDistributor = IMerklDistributor(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae); //https://app.merkl.xyz/status
    IrEUL constant rEUL = IrEUL(0x1b0e3Da51b2517E09aE74CD31b708e46B9158E8b); // https://docs.euler.finance/EUL/addresses

    IEulerVault constant eulerUSDCVault1 = IEulerVault(0x6eAe95ee783e4D862867C4e0E4c3f4B95AA682Ba); // https://app.euler.finance/?asset=USDT&network=unichain
    IEulerVault constant eulerWETHVault1 = IEulerVault(0x1f3134C3f3f8AdD904B9635acBeFC0eA0D0E1ffC); // https://app.euler.finance/vault/0x1f3134C3f3f8AdD904B9635acBeFC0eA0D0E1ffC?network=unichain
    IEulerVault constant eulerWSTETHVault1 = IEulerVault(0x54ff502df96CD9B9585094EaCd86AAfCe902d06A);
    IEulerVault constant eulerUSDTVault1 = IEulerVault(0xD49181c522eCDB265f0D9C175Cf26FFACE64eAD3);
    IEulerVault constant eulerWBTCVault1 = IEulerVault(0x5d2511C1EBc795F4394f7f659f693f8C15796485);

    // ** Uniswap
    IUniversalRouter constant UNIVERSAL_ROUTER = IUniversalRouter(0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3); // https://docs.uniswap.org/contracts/v4/deployments
    IPermit2 constant PERMIT_2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3); // https://docs.uniswap.org/contracts/v4/deployments
    IV4Quoter constant V4_QUOTER = IV4Quoter(0x333E3C607B141b18fF6de9f258db6e77fE7491E0);

    // ** Chronicle
    IAggV3 constant chronicle_feed_WETH = IAggV3(0x152598809FB59db55cA76f89a192Fb23555531D8);
    IAggV3 constant chronicle_feed_WSTETH = IAggV3(0x74661a9ea74fD04975c6eBc6B155Abf8f885636c);
    IAggV3 constant chronicle_feed_USDC = IAggV3(0x5e9Aae684047a0ACf2229fAefE8b46726335CE77);
    IAggV3 constant chronicle_feed_USDT = IAggV3(0x8E947Ea7D5881Cd600Ace95F1201825F8C708844);
    IAggV3 constant chronicle_feed_WBTC = IAggV3(0x1F852F2Fe663c90f454476dd62491C5717F506F2);
    IAggV3 constant zero_feed = IAggV3(address(0));

    // ** Api3
    IAggV3 constant api3_feed_USDC = IAggV3(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f);
    IAggV3 constant api3_feed_WETH = IAggV3(0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473);
}
/// forge-lint: disable-end(screaming-snake-case-const)
