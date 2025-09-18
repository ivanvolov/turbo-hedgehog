// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** external imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {AggregatorV3Interface as IAggV3} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IMerklDistributor} from "@merkl-contracts/IMerklDistributor.sol";
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {IEthereumVaultConnector as IEVC} from "@euler-interfaces/IEVC.sol";
import {IRewardToken as IrEUL} from "@euler-interfaces/IRewardToken.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {BaseStrategyHook} from "@src/core/base/BaseStrategyHook.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {MorphoFlashLoanAdapter} from "@src/core/flashLoanAdapters/MorphoFlashLoanAdapter.sol";
import {EulerLendingAdapter} from "@src/core/lendingAdapters/EulerLendingAdapter.sol";
import {Oracle} from "@src/core/oracles/Oracle.sol";
import {PositionManager} from "@src/core/positionManagers/PositionManager.sol";
import {UnicordPositionManager} from "@src/core/positionManagers/UnicordPositionManager.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";
import {TestFeed} from "@test/simulations/TestFeed.sol";
import {DeployUtils} from "./DeployUtils.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";

// ** interfaces
import {IPositionManagerStandard} from "@test/interfaces/IPositionManagerStandard.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IOracleTest} from "@test/interfaces/IOracleTest.sol";

contract DeployALM is DeployUtils {
    // ** Strategy params
    int8 decimalsDelta;
    uint256 public longLeverage;
    uint256 public shortLeverage;
    uint256 public weight;
    uint256 public liquidityMultiplier;
    uint256 public slippage;
    uint24 feeLP;
    uint160 initialSQRTPrice;
    bool isInvertedAssets;
    bool isInvertedPool;
    bool isInvertedPoolInOracle;
    bool isNova;
    uint256 protocolFee;
    uint256 tvlCap;
    int24 tickLowerDelta;
    int24 tickUpperDelta;
    uint256 swapPriceThreshold;
    uint256 k1;
    uint256 k2;

    address treasury;
    address rebalanceOperator;
    address swapOperator;
    address liquidityOperator;

    uint256 rebalancePriceThreshold;
    uint256 rebalanceTimeThreshold;
    uint256 maxDeviationLong;
    uint256 maxDeviationShort;

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
        vm.startBroadcast(deployerKey);
        alm = new ALM(BASE, QUOTE, isInvertedAssets, "NAME", "SYMBOL");
        alm.setTVLCap(tvlCap);
        vm.stopBroadcast();

        deploy_hook_contract();

        vm.startBroadcast(deployerKey);
        // ** adapters
        swapAdapter = new UniswapSwapAdapter(BASE, QUOTE, universalRouter, manager, PERMIT_2, WETH9);
        rebalanceAdapter = new SRebalanceAdapter(BASE, QUOTE, isInvertedAssets, isNova);
        _setComponents(address(alm));
        _setComponents(address(hook));
        _setComponents(address(lendingAdapter));
        _setComponents(address(flashLoanAdapter));
        _setComponents(address(positionManager));
        _setComponents(address(swapAdapter));
        _setComponents(address(rebalanceAdapter));
        hook.setProtocolParams(liquidityMultiplier, protocolFee, tickLowerDelta, tickUpperDelta, swapPriceThreshold);
        if (swapOperator != address(0)) hook.setOperator(swapOperator);
        if (liquidityOperator != address(0)) hook.setOperator(liquidityOperator);
        if (rebalanceOperator != address(0)) rebalanceAdapter.setRebalanceOperator(rebalanceOperator);
        rebalanceAdapter.setLastRebalanceSnapshot(oracle.price(), initialSQRTPrice, 0);

        // ** initialize pool
        manager.initialize(poolKey, initialSQRTPrice);
        vm.stopBroadcast();
    }

    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function deploy_hook_contract() internal returns (bytes32 salt) {
        IWETH9 WETH9_or_zero = IS_NTS ? WETH9 : TestLib.ZERO_WETH9;
        bytes memory constructorArgs = abi.encode(deployerAddress, BASE, QUOTE, WETH9_or_zero, isInvertedPool, manager);
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG
        );
        address _hookAddress;
        (_hookAddress, salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(BaseStrategyHook).creationCode,
            constructorArgs
        );
        vm.startBroadcast(deployerKey);
        hook = new BaseStrategyHook{salt: salt}(deployerAddress, BASE, QUOTE, WETH9_or_zero, isInvertedPool, manager);
        vm.stopBroadcast();

        poolKey = constructPoolKey();
        require(address(hook) == _hookAddress, "PointsHookScript: hook address mismatch");
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

    TestFeed feed0;
    TestFeed feed1;

    function deploy_oracle_with_test_feeds() internal {
        feed0 = new TestFeed(999700000000000000, 18);
        feed1 = new TestFeed(4612052471000000000000, 18);

        oracle = new Oracle(feed0, feed1, isInvertedPoolInOracle, decimalsDelta);
        IOracleTest(address(oracle)).setStalenessThresholds(stalenessThresholdB, stalenessThresholdQ);
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

    function dealETH(address to, uint256 amount) public {
        uint256 testDeployerKey = vm.envUint("TEST_ANVIL_PRIVATE_KEY_DEPLOYER");
        vm.broadcast(testDeployerKey);
        payable(to).transfer(amount);
    }

    uint256 public mainnetDepositAmount = 224250000000000; // ~ 1$
    uint256 public testDepositAmount = 1 ether / 100; // ~ 46$
}
