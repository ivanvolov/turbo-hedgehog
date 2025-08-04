// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {Currency} from "v4-core/types/Currency.sol";
import {IUniversalRouter} from "@universal-router/IUniversalRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {V4Quoter} from "v4-periphery/src/lens/V4Quoter.sol";

// ** contracts
import {TestBaseMorpho} from "./common/TestBaseMorpho.sol";
import {ALM} from "@src/ALM.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";
import {UniversalRouter} from "@universal-router/contracts/UniversalRouter.sol";
import {RouterParameters} from "@universal-router/contracts/types/RouterParameters.sol";

// ** libraries
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";

abstract contract ALMTestBaseUnichain is TestBaseMorpho {
    using SafeERC20 for IERC20;

    function init_hook(
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
        WETH9 = UConstants.WETH9;
        deploy_hook_contract(_isInvertedAssets, UConstants.WETH9);
        isInvertedAssets = _isInvertedAssets;

        createPositionManager(_isNova);
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

    function deployMockUniversalRouter() internal {
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

    function deployMockV4Quoter() internal {
        quoter = new V4Quoter(manager);
    }

    function approve_accounts() public virtual override {
        super.approve_accounts();

        _approvePermitIfNotEth(BASE, marketMaker.addr);
        _approvePermitIfNotEth(QUOTE, marketMaker.addr);

        _approvePermitIfNotEth(BASE, swapper.addr);
        _approvePermitIfNotEth(QUOTE, swapper.addr);
    }

    function _approvePermitIfNotEth(IERC20 TOKEN, address user) private {
        if (address(TOKEN) == address(ETH)) return;
        // console.log("_approvePermitIfNotEth: %s", address(TOKEN));
        vm.startPrank(user);
        TOKEN.forceApprove(address(UConstants.PERMIT_2), type(uint256).max);
        UConstants.PERMIT_2.approve(address(TOKEN), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }
}
