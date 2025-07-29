// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** interfaces
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {ISwapRouter} from "@uniswap-v3/ISwapRouter.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {IEthereumVaultConnector as IEVC} from "@euler-interfaces/IEVC.sol";
import {IRewardToken as IrEUL} from "@euler-interfaces/IRewardToken.sol";
import {IMerklDistributor} from "@merkl-contracts/IMerklDistributor.sol";
import {IUniversalRewardsDistributor} from "@universal-rewards-distributor/IUniversalRewardsDistributor.sol";
import {IUniversalRouter} from "@universal-router/IUniversalRouter.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

library Constants {
    IPoolManager constant manager = IPoolManager(0x1F98400000000000000000000000000000000004);

    // ** ERC20 tokens
    address constant WETH = 0x4200000000000000000000000000000000000006;
    IWETH9 constant WETH9 = IWETH9(0x4200000000000000000000000000000000000006);
    address constant USDC = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;
    address constant USDT = 0x9151434b16b9763660705744891fA906F660EcC5;

    // ** Morpho
    IMorpho constant MORPHO = IMorpho(0x8f5ae9CddB9f68de460C77730b018Ae7E04a140A); // https://docs.morpho.org/getting-started/resources/addresses/
    IERC4626 constant morphoUSDCVault = IERC4626(0x38f4f3B6533de0023b9DCd04b02F93d36ad1F9f9);

    // ** Euler
    IEVC constant EULER_VAULT_CONNECT = IEVC(payable(0x2A1176964F5D7caE5406B627Bf6166664FE83c60)); // https://github.com/euler-xyz/euler-interfaces/tree/master/addresses/130
    IMerklDistributor constant merklRewardsDistributor = IMerklDistributor(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae); //https://app.merkl.xyz/status
    IrEUL constant rEUL = IrEUL(0x1b0e3Da51b2517E09aE74CD31b708e46B9158E8b); // https://docs.euler.finance/EUL/addresses

    IEulerVault constant eulerUSDCVault1 = IEulerVault(0x6eAe95ee783e4D862867C4e0E4c3f4B95AA682Ba); // https://app.euler.finance/?asset=USDT&network=unichain
    IEulerVault constant eulerWETHVault1 = IEulerVault(0x1f3134C3f3f8AdD904B9635acBeFC0eA0D0E1ffC);
    IEulerVault constant eulerUSDTVault1 = IEulerVault(0xD49181c522eCDB265f0D9C175Cf26FFACE64eAD3);

    // ** Uniswap
    IUniversalRouter constant UNIVERSAL_ROUTER = IUniversalRouter(0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3); // https://docs.uniswap.org/contracts/v4/deployments
    IPermit2 constant PERMIT_2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3); // https://docs.uniswap.org/contracts/v4/deployments
}
