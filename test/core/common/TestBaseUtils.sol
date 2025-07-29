// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** V4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Deployers} from "@test/libraries/v4-forks/Deployers.sol";
import {V4Quoter} from "v4-periphery/src/lens/V4Quoter.sol";
import {IUniversalRouter} from "@universal-router/IUniversalRouter.sol";

// ** contracts
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";

// ** libraries
import {PRBMathUD60x18} from "@test/libraries/math/PRBMathUD60x18.sol";
import {TestAccount} from "@test/libraries/TestAccountLib.t.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {IFlashLoanAdapter} from "@src/interfaces/IFlashLoanAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {ISwapAdapter} from "@src/interfaces/swapAdapters/ISwapAdapter.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

abstract contract TestBaseUtils is Deployers {
    using PRBMathUD60x18 for uint256;

    PoolKey unauthorizedKey;
    V4Quoter quoter;
    IUniversalRouter universalRouter;
    uint160 initialSQRTPrice;
    ALM hook;
    SRebalanceAdapter rebalanceAdapter;

    string UNICHAIN_RPC_URL = vm.envString("UNICHAIN_RPC_URL");
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    address public TARGET_SWAP_POOL;

    IERC20 BASE;
    IERC20 QUOTE;
    string baseName;
    string quoteName;
    uint8 bDec;
    uint8 qDec;
    bool isInvertedPool = true;

    ILendingAdapter lendingAdapter;
    IFlashLoanAdapter flashLoanAdapter;
    IPositionManager positionManager;
    ISwapAdapter swapAdapter;
    IOracle oracle;

    TestAccount deployer;
    TestAccount alice;
    TestAccount migrationContract;
    TestAccount swapper;
    TestAccount marketMaker;
    TestAccount zero;
    TestAccount treasury;

    uint256 almId;
    uint256 tempGas;

    uint256 constant WAD = 1e18;
    IERC20 ETH = IERC20(address(0));

    function _test_currencies_order(address token0, address token1) internal pure {
        if (token0 >= token1) revert("Out of order");
    }

    function calcTVL() internal view returns (uint256) {
        return hook.TVL(oracle.price());
    }

    function calcSharePrice(uint256 tS, uint256 TVL) internal pure returns (uint256) {
        if (tS == 0) return 0;
        return TVL.div(tS);
    }

    function recordGas() internal {
        tempGas = gasleft();
    }

    function logGas() internal {
        console.log("gasSpend", tempGas - gasleft());
        tempGas = 0;
    }

    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }

    function _fakeSetComponents(address adapter, address fakeALM) internal {
        vm.mockCall(fakeALM, abi.encodeWithSelector(IALM.status.selector), abi.encode(0));
        vm.prank(deployer.addr);
        IBase(adapter).setComponents(
            IALM(fakeALM),
            ILendingAdapter(alice.addr),
            IFlashLoanAdapter(alice.addr),
            IPositionManager(alice.addr),
            IOracle(alice.addr),
            IRebalanceAdapter(alice.addr),
            ISwapAdapter(alice.addr)
        );
    }

    function otherToken(IERC20 token) internal view returns (IERC20) {
        if (token == BASE) return QUOTE;
        if (token == QUOTE) return BASE;
        revert("Token not allowed");
    }

    function poolPrice() internal view returns (uint256 _poolPrice) {
        (, _poolPrice) = oracle.poolPrice();
    }

    function oraclePriceW() internal view returns (uint256) {
        uint256 ratio = 10 ** uint256(int256(int8(bDec) - int8(qDec)) + 18);
        return oracle.price().div(ratio);
    }

    function oraclePrice() internal view returns (uint256) {
        return oracle.price();
    }
}
