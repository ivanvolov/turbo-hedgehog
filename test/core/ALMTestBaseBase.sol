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
import {PositionManager} from "@src/core/positionManagers/PositionManager.sol";
import {UnicordPositionManager} from "@src/core/positionManagers/UnicordPositionManager.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";
import {UniversalRouter} from "@universal-router/contracts/UniversalRouter.sol";
import {RouterParameters} from "@universal-router/contracts/types/RouterParameters.sol";

// ** libraries
import {Constants as BConstants} from "@test/libraries/constants/BaseConstants.sol";

abstract contract ALMTestBaseBase is TestBaseMorpho {
    using SafeERC20 for IERC20;

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
        WETH9 = BConstants.WETH9;
        deploy_hook_contract(_isInvertedAssets, BConstants.WETH9);
        isInvertedAssets = _isInvertedAssets;

        if (_isNova) positionManager = new UnicordPositionManager(BASE, QUOTE);
        else positionManager = new PositionManager(BASE, QUOTE);

        swapAdapter = new UniswapSwapAdapter(BASE, QUOTE, universalRouter, BConstants.PERMIT_2, BConstants.WETH9);
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
            v2Factory: 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6,
            v3Factory: 0x33128a8fC17869897dcE68Ed026d694621f6FDfD,
            pairInitCodeHash: 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f,
            poolInitCodeHash: 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54,
            v4PoolManager: 0x498581fF718922c3f8e6A244956aF099B2652b2b,
            v3NFTPositionManager: 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1,
            v4PositionManager: 0x7C5f5A4bBd8fD63184577525326123B519429bDc
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
        TOKEN.forceApprove(address(BConstants.PERMIT_2), type(uint256).max);
        BConstants.PERMIT_2.approve(address(TOKEN), address(universalRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }
}
