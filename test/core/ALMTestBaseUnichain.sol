// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** V4 imports
import {Currency} from "v4-core/types/Currency.sol";
import {IUniversalRouter} from "@universal-router/IUniversalRouter.sol";

// ** contracts
import {TestBaseMorpho} from "./common/TestBaseMorpho.sol";
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {PositionManager} from "@src/core/positionManagers/PositionManager.sol";
import {UnicordPositionManager} from "@src/core/positionManagers/UnicordPositionManager.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";
import {UniversalRouter} from "@universal-router/contracts/UniversalRouter.sol";
import {RouterParameters} from "@universal-router/contracts/types/RouterParameters.sol";

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

        swapAdapter = new UniswapSwapAdapter(BASE, QUOTE, universalRouter, UConstants.PERMIT_2, UConstants.WETH9);
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

    function deployMockUniversalRouter() internal returns (UniversalRouter) {
        RouterParameters memory params = RouterParameters({
            permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3,
            weth9: 0x4200000000000000000000000000000000000006,
            v2Factory: 0x1F98400000000000000000000000000000000002,
            v3Factory: 0x1F98400000000000000000000000000000000003,
            pairInitCodeHash: 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f,
            poolInitCodeHash: 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54,
            v4PoolManager: 0x1F98400000000000000000000000000000000004,
            v3NFTPositionManager: 0x943e6e07a7E8E791dAFC44083e54041D743C46E9,
            v4PositionManager: 0x4529A01c7A0410167c5740C487A8DE60232617bf
        });
        universalRouter = IUniversalRouter(address(new UniversalRouter(params)));
    }
}
