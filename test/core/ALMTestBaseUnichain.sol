// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** V4 imports
import {Currency} from "v4-core/types/Currency.sol";

// ** contracts
import {TestBaseMorpho} from "./common/TestBaseMorpho.sol";
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {PositionManager} from "@src/core/positionManagers/PositionManager.sol";
import {UnicordPositionManager} from "@src/core/positionManagers/UnicordPositionManager.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

abstract contract ALMTestBaseUnichain is TestBaseMorpho {
    function production_init_hook(
        bool _isInvertedAssets,
        bool _isNova,
        uint256 _liquidityMultiplier,
        uint256 _protocolFee,
        uint256 _tvlCap,
        int24 _tickLowerDelta,
        int24 _tickUpperDelta,
        uint256 _swapPriceThreshold
    ) internal {
        vm.startPrank(deployer.addr);
        deploy_hook_contract(_isInvertedAssets, UConstants.WETH9);
        isInvertedAssets = _isInvertedAssets;

        if (_isNova) positionManager = new UnicordPositionManager(BASE, QUOTE);
        else positionManager = new PositionManager(BASE, QUOTE);

        swapAdapter = new UniswapSwapAdapter(
            BASE,
            QUOTE,
            UConstants.UNIVERSAL_ROUTER,
            UConstants.PERMIT_2,
            UConstants.WETH9
        );
        rebalanceAdapter = new SRebalanceAdapter(BASE, QUOTE, _isInvertedAssets, _isNova);
        hook.setProtocolParams(
            _liquidityMultiplier,
            _protocolFee,
            _tvlCap,
            _tickLowerDelta,
            _tickUpperDelta,
            _swapPriceThreshold
        );
        _setComponents(address(hook));
        _setComponents(address(lendingAdapter));
        _setComponents(address(flashLoanAdapter));
        _setComponents(address(positionManager));
        _setComponents(address(swapAdapter));
        _setComponents(address(rebalanceAdapter));
        rebalanceAdapter.setRebalanceOperator(deployer.addr);
        rebalanceAdapter.setLastRebalanceSnapshot(oracle.price(), initialSQRTPrice, 0);

        initPool(key.currency0, key.currency1, key.hooks, key.fee, key.tickSpacing, initialSQRTPrice);
        vm.stopPrank();
    }
}
