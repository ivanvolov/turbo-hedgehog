// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** external imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Constants} from "v4-core-test/utils/Constants.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";
import {IUniversalRouter} from "@universal-router/IUniversalRouter.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {AggregatorV3Interface as IAggV3} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IMerklDistributor} from "@merkl-contracts/IMerklDistributor.sol";
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {IEVC as EVCLib, IEthereumVaultConnector as IEVC} from "@euler-interfaces/IEVC.sol";
import {IRewardToken as IrEUL} from "@euler-interfaces/IRewardToken.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {BaseStrategyHook} from "@src/core/base/BaseStrategyHook.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {MorphoLendingAdapter} from "@src/core/lendingAdapters/MorphoLendingAdapter.sol";
import {MorphoFlashLoanAdapter} from "@src/core/flashLoanAdapters/MorphoFlashLoanAdapter.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {EulerFlashLoanAdapter} from "@src/core/flashLoanAdapters/EulerFlashLoanAdapter.sol";
import {Oracle} from "@src/core/oracles/Oracle.sol";
import {PositionManager} from "@src/core/positionManagers/PositionManager.sol";
import {UnicordPositionManager} from "@src/core/positionManagers/UnicordPositionManager.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {IFlashLoanAdapter} from "@src/interfaces/IFlashLoanAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IPositionManagerStandard} from "@test/interfaces/IPositionManagerStandard.sol";
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IOracleTest} from "@test/interfaces/IOracleTest.sol";

contract DeployALM {
    uint256 deployerKey;

    // ** Network specific constants
    IERC20 ETH = IERC20(address(0));
    IWETH9 WETH9;
    IPermit2 PERMIT_2;
    IPoolManager manager;
    IUniversalRouter universalRouter;
    IV4Quoter quoter;

    // ** Deployed contracts
    ALM alm;
    BaseStrategyHook hook;
    address hookAddress;
    PoolKey key;
    SRebalanceAdapter rebalanceAdapter;
    IFlashLoanAdapter flashLoanAdapter;
    ILendingAdapter lendingAdapter;
    IPositionManagerStandard positionManager;
    IOracle oracle;
    ISwapAdapter swapAdapter;

    // ** Strategy params
    string TOKEN_NAME;
    string TOKEN_SYMBOL;
    IERC20 BASE;
    IERC20 QUOTE;
    int8 decimalsDelta;
    uint256 public longLeverage;
    uint256 public shortLeverage;
    uint256 public weight;
    uint256 public liquidityMultiplier;
    uint256 public slippage;
    uint24 feeLP;
    uint160 initialSQRTPrice;
    bool IS_NTS;
    bool isInvertedAssets;
    bool isInvertedPool;
    bool isInvertedPoolInOracle;
    bool isNova;
    uint256 protocolFee;
    uint256 tvlCap;
    int24 tickLowerDelta;
    int24 tickUpperDelta;
    uint256 swapPriceThreshold;

    // ** Adapter params
    IAggV3 feedB;
    IAggV3 feedQ;
    uint24 stalenessThresholdB;
    uint24 stalenessThresholdQ;
    IMorpho morpho;
    IEVC ethereumVaultConnector;
    IEulerVault vault0;
    IEulerVault vault1;
    IMerklDistributor merklRewardsDistributor;
    IrEUL rEUL;

    function deploy_and_init_hook() internal {
        // ** main parts
        alm = new ALM(BASE, QUOTE, isInvertedAssets, "NAME", "SYMBOL");
        alm.setTVLCap(tvlCap);
        deploy_hook_contract();

        // ** adapters
        swapAdapter = new UniswapSwapAdapter(BASE, QUOTE, universalRouter, manager, PERMIT_2, WETH9);
        rebalanceAdapter = new SRebalanceAdapter(BASE, QUOTE, isInvertedAssets, isNova);
        hook.setProtocolParams(liquidityMultiplier, protocolFee, tickLowerDelta, tickUpperDelta, swapPriceThreshold);
        // _setComponents(address(alm));
        // _setComponents(address(hook));
        // _setComponents(address(lendingAdapter));
        // _setComponents(address(flashLoanAdapter));
        // _setComponents(address(positionManager));
        // _setComponents(address(swapAdapter));
        // _setComponents(address(rebalanceAdapter));
        // rebalanceAdapter.setRebalanceOperator(address(this));
        // rebalanceAdapter.setLastRebalanceSnapshot(oracle.price(), initialSQRTPrice, 0);

        // ** initialize pool
        // manager.initialize(key, initialSQRTPrice);
    }

    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function deploy_hook_contract() internal returns (bytes32 salt) {
        IWETH9 WETH9_or_zero = IS_NTS ? WETH9 : TestLib.ZERO_WETH9;
        bytes memory constructorArgs = abi.encode(BASE, QUOTE, WETH9_or_zero, isInvertedPool, manager);
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG
        );
        (hookAddress, salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(BaseStrategyHook).creationCode,
            constructorArgs
        );

        (address currency0, address currency1) = getHookCurrenciesInOrder();
        key = PoolKey(
            Currency.wrap(currency0),
            Currency.wrap(currency1),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            1, // The value of tickSpacing doesn't change with dynamic fees, so it does matter.
            IHooks(hookAddress)
        );
        hook = new BaseStrategyHook{salt: salt}(BASE, QUOTE, WETH9_or_zero, isInvertedPool, manager);
        require(address(hook) == hookAddress, "PointsHookScript: hook address mismatch");
    }

    function getHookCurrenciesInOrder() internal view returns (address currency0, address currency1) {
        (currency0, currency1) = (address(BASE), address(QUOTE));
        if (IS_NTS) {
            if (currency0 == address(WETH9)) currency0 = address(ETH);
            if (currency1 == address(WETH9)) currency1 = address(ETH);
        }
        if (currency0 >= currency1) (currency0, currency1) = (currency1, currency0);

        console.log(">> key currency0: %s", currency0);
        console.log(">> key currency1: %s", currency1);
    }

    function deploy_fl_adapter_morpho() internal {
        flashLoanAdapter = new MorphoFlashLoanAdapter(BASE, QUOTE, morpho);
    }

    function deploy_lending_adapter_euler() internal {
        lendingAdapter = new EulerLendingAdapter(
            BASE,
            QUOTE,
            ethereumVaultConnector,
            vault0,
            vault1,
            merklRewardsDistributor,
            rEUL
        );
    }

    function deploy_oracle() internal {
        oracle = new Oracle(feedB, feedQ, isInvertedPoolInOracle, decimalsDelta);
        IOracleTest(address(oracle)).setStalenessThresholds(stalenessThresholdB, stalenessThresholdQ);
    }

    function deploy_position_manager() internal {
        IPositionManager _positionManager;
        if (isNova) _positionManager = new UnicordPositionManager(BASE, QUOTE);
        else _positionManager = new PositionManager(BASE, QUOTE);
        positionManager = IPositionManagerStandard(address(_positionManager));
    }

    function _setComponents(address module) internal {
        IBase(module).setComponents(
            alm,
            hook,
            lendingAdapter,
            flashLoanAdapter,
            positionManager,
            oracle,
            rebalanceAdapter,
            swapAdapter
        );
    }
}
