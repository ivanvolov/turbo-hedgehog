// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// forge-lint: disable-start(screaming-snake-case-const)

// ** interfaces
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
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
    IPoolManager constant manager = IPoolManager(0x498581fF718922c3f8e6A244956aF099B2652b2b);

    // ** ERC20 tokens
    IWETH9 constant WETH9 = IWETH9(0x4200000000000000000000000000000000000006);
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    // ** Morpho
    IMorpho constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // https://docs.morpho.org/getting-started/resources/addresses/

    // ** Euler
    IEVC constant EULER_VAULT_CONNECT = IEVC(payable(0x5301c7dD20bD945D2013b48ed0DEE3A284ca8989)); // https://github.com/euler-xyz/euler-interfaces/tree/master/addresses/130
    IMerklDistributor constant merklRewardsDistributor = IMerklDistributor(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae); //https://app.merkl.xyz/status
    IrEUL constant rEUL = IrEUL(0xE08e1f00D388E201e48842E53fA96195568e6813); // https://docs.euler.finance/EUL/addresses

    // https://app.euler.finance/?asset=USDT&network=base
    IEulerVault constant eulerUSDCVault1 = IEulerVault(0x0A1a3b5f2041F33522C4efc754a7D096f880eE16);
    IEulerVault constant eulerCBBTCVault1 = IEulerVault(0x882018411Bc4A020A879CEE183441fC9fa5D7f8B);

    // ** Uniswap
    IUniversalRouter constant UNIVERSAL_ROUTER = IUniversalRouter(0x6fF5693b99212Da76ad316178A184AB56D299b43); // https://docs.uniswap.org/contracts/v4/deployments
    IPermit2 constant PERMIT_2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3); // https://docs.uniswap.org/contracts/v4/deployments
    IV4Quoter constant V4_QUOTER = IV4Quoter(0x0d5e0F971ED27FBfF6c2837bf31316121532048D);

    // ** Chainlink // https://data.chain.link/feeds/ethereum/mainnet/usdt-usd
    IAggV3 constant chainlink_feed_CBBTC = IAggV3(0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D);
    IAggV3 constant chainlink_feed_USDC = IAggV3(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B);
    IAggV3 constant chainlink_feed_WETH = IAggV3(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70);
    IAggV3 constant chainlink_feed_WSTETH = IAggV3(0x43a5C292A453A3bF3606fa856197f09D7B74251a);
}
/// forge-lint: disable-end(screaming-snake-case-const)
