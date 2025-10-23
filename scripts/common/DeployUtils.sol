// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// ** external imports
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";
import {IUniversalRouter} from "@universal-router/IUniversalRouter.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IPermit2} from "v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {BaseStrategyHook} from "@src/core/base/BaseStrategyHook.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {Oracle} from "@src/core/oracles/Oracle.sol";
import {PositionManager} from "@src/core/positionManagers/PositionManager.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IFlashLoanAdapter} from "@src/interfaces/IFlashLoanAdapter.sol";
import {IPositionManagerStandard} from "@test/interfaces/IPositionManagerStandard.sol";
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {IUniswapSwapAdapter} from "@test/interfaces/IUniswapSwapAdapter.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

abstract contract DeployUtils is Script {
    using SafeERC20 for IERC20;
    uint256 deployerKey;
    address deployerAddress;

    uint256 swapperKey;
    address swapperAddress;

    uint256 depositorKey;
    address depositorAddress;

    // ** Strategy params
    string TOKEN_NAME;
    string TOKEN_SYMBOL;
    IERC20 BASE;
    IERC20 QUOTE;
    bool IS_NTS;

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
    PoolKey poolKey;
    SRebalanceAdapter rebalanceAdapter;
    IFlashLoanAdapter flashLoanAdapter;
    ILendingAdapter lendingAdapter;
    IPositionManagerStandard positionManager;
    IOracle oracle;
    ISwapAdapter swapAdapter;

    function getAndCheckPoolKey(
        IERC20 token0,
        IERC20 token1,
        uint24 fee,
        int24 tickSpacing,
        bytes32 _poolId
    ) internal pure returns (PoolKey memory _poolKey) {
        _test_currencies_order(address(token0), address(token1));
        _poolKey = PoolKey(
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            fee,
            tickSpacing,
            IHooks(address(0))
        );
        PoolId id = _poolKey.toId();
        require(PoolId.unwrap(id) == _poolId, "PoolId not equal");
    }

    function constructPoolKey() internal view returns (PoolKey memory _poolKey) {
        (address currency0, address currency1) = getHookCurrenciesInOrder();
        _poolKey = PoolKey(
            Currency.wrap(currency0),
            Currency.wrap(currency1),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            1,
            IHooks(address(hook))
        );
        // console.log("PoolID: %s");
        // console.logBytes32(PoolId.unwrap(_poolKey.toId()));
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

    function _test_currencies_order(address token0, address token1) internal pure {
        if (token0 >= token1) revert("Out of order");
    }

    function setSwapAdapterToV4SingleSwap(PoolKey memory targetKey, uint8[4] memory config) internal {
        IUniswapSwapAdapter(address(swapAdapter)).setRoutesOperator(deployerAddress);

        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(0, 2, abi.encode(false, targetKey, true, bytes("")));
        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(1, 2, abi.encode(true, targetKey, true, bytes("")));
        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(2, 2, abi.encode(false, targetKey, false, bytes("")));
        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(3, 2, abi.encode(true, targetKey, false, bytes("")));

        uint256[] memory activeSwapRoute = new uint256[](1);
        activeSwapRoute[0] = config[0];
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, true, activeSwapRoute); // exactIn, base => quote

        activeSwapRoute[0] = config[1];
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, false, activeSwapRoute); // exactOut, quote => base

        activeSwapRoute[0] = config[2];
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, true, activeSwapRoute); // exactOut, base => quote

        activeSwapRoute[0] = config[3];
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, false, activeSwapRoute); // exactIn, quote => base
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

    function approvePermitIfNotEth(IERC20 TOKEN) internal {
        if (address(TOKEN) == address(ETH)) return;
        TOKEN.forceApprove(address(PERMIT_2), type(uint256).max);
        PERMIT_2.approve(address(TOKEN), address(universalRouter), type(uint160).max, type(uint48).max);
    }

    function loadActorsAnvil() internal {
        deployerKey = vm.envUint("TEST_ANVIL_PRIVATE_KEY_DEPLOYER");
        deployerAddress = vm.addr(deployerKey);
        swapperKey = vm.envUint("TEST_ANVIL_PRIVATE_KEY_SWAPPER");
        swapperAddress = vm.addr(swapperKey);
        depositorKey = vm.envUint("TEST_ANVIL_PRIVATE_KEY_DEPOSITOR");
        depositorAddress = vm.addr(depositorKey);
    }

    function loadActorsUNI() internal {
        deployerKey = vm.envUint("PROD_UNI_PRIVATE_KEY_DEPLOYER");
        deployerAddress = vm.addr(deployerKey);
        swapperKey = vm.envUint("PROD_UNI_PRIVATE_KEY_SWAPPER");
        swapperAddress = vm.addr(swapperKey);
        depositorKey = vm.envUint("PROD_UNI_PRIVATE_KEY_DEPOSITOR");
        depositorAddress = vm.addr(depositorKey);
    }

    function saveComponentAddresses() internal {
        // Log deployed contract addresses
        console.log("\n=== Deployed Contract Addresses ===");
        console.log("ALM:                %s", address(alm));
        console.log("Hook:               %s", address(hook));
        console.log("RebalanceAdapter:   %s", address(rebalanceAdapter));
        console.log("Oracle:             %s", address(oracle));
        console.log("PositionManager:    %s", address(positionManager));
        console.log("FlashLoanAdapter:   %s", address(flashLoanAdapter));
        console.log("LendingAdapter:     %s", address(lendingAdapter));
        console.log("===================================\n");

        // Serialize addresses to JSON
        string memory json = "deployments";
        vm.serializeAddress(json, "alm", address(alm));
        vm.serializeAddress(json, "hook", address(hook));
        vm.serializeAddress(json, "rebalanceAdapter", address(rebalanceAdapter));
        vm.serializeAddress(json, "oracle", address(oracle));
        vm.serializeAddress(json, "positionManager", address(positionManager));
        vm.serializeAddress(json, "flashLoanAdapter", address(flashLoanAdapter));
        string memory finalJson = vm.serializeAddress(json, "lendingAdapter", address(lendingAdapter));

        // Write to broadcast folder
        string memory deploymentPath = "./broadcast/custom_unichain_broadcast.json";
        vm.writeJson(finalJson, deploymentPath);
    }

    function saveOracleAddresses() internal {
        console.log("\n=== Deployed Oracle Addresses ===");
        console.log("Oracle:             %s", address(oracle));
        console.log("===================================\n");

        // Serialize addresses to JSON
        string memory json = "deployments";
        string memory finalJson = vm.serializeAddress(json, "oracle", address(oracle));

        // Write to broadcast folder
        string memory deploymentPath = "./broadcast/custom_unichain_oracle_broadcast.json";
        vm.writeJson(finalJson, deploymentPath);
    }

    function loadOracleAddress() internal {
        string memory deploymentPath = "./broadcast/custom_unichain_oracle_broadcast.json";
        string memory json = vm.readFile(deploymentPath);

        // Parse addresses from JSON
        address oracleAddress = vm.parseJsonAddress(json, ".oracle");
        console.log("oracleAddress %s", oracleAddress);

        oracle = IOracle(oracleAddress);
    }

    function loadComponentAddresses() internal {
        // Write to broadcast folder
        string memory deploymentPath = "./broadcast/custom_unichain_broadcast.json";
        string memory json = vm.readFile(deploymentPath);

        // Parse addresses from JSON
        address almAddress = vm.parseJsonAddress(json, ".alm");
        address hookAddress = vm.parseJsonAddress(json, ".hook");
        address rebalanceAdapterAddress = vm.parseJsonAddress(json, ".rebalanceAdapter");
        address oracleAddress = vm.parseJsonAddress(json, ".oracle");
        address positionManagerAddress = vm.parseJsonAddress(json, ".positionManager");
        address flashLoanAdapterAddress = vm.parseJsonAddress(json, ".flashLoanAdapter");
        address lendingAdapterAddress = vm.parseJsonAddress(json, ".lendingAdapter");

        // Cast to appropriate contract types
        alm = ALM(almAddress);
        hook = BaseStrategyHook(payable(hookAddress));
        rebalanceAdapter = SRebalanceAdapter(rebalanceAdapterAddress);
        oracle = IOracle(oracleAddress);
        positionManager = IPositionManagerStandard(positionManagerAddress);
        flashLoanAdapter = IFlashLoanAdapter(flashLoanAdapterAddress);
        lendingAdapter = ILendingAdapter(lendingAdapterAddress);
    }

    function setup_network_specific_addresses_unichain() internal {
        PERMIT_2 = UConstants.PERMIT_2;
        WETH9 = UConstants.WETH9;
        manager = UConstants.manager;
        universalRouter = UConstants.UNIVERSAL_ROUTER;
        quoter = UConstants.V4_QUOTER;
    }
}
