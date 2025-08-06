// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** V4 imports
import {V4Quoter} from "v4-periphery/src/lens/V4Quoter.sol";

// ** contracts
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";
import {SRebalanceAdapter} from "@src/core/SRebalanceAdapter.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {TestBaseMorpho} from "./common/TestBaseMorpho.sol";

abstract contract ALMTestBase is TestBaseMorpho {
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
        console.log("oracle: initialPrice %s", oraclePriceW());
        vm.startPrank(deployer.addr);
        WETH9 = MConstants.WETH9;
        deploy_hook_contract(_isInvertedAssets, MConstants.WETH9);
        isInvertedAssets = _isInvertedAssets;

        createPositionManager(_isNova);
        swapAdapter = new UniswapSwapAdapter(
            BASE,
            QUOTE,
            MConstants.UNIVERSAL_ROUTER,
            MConstants.PERMIT_2,
            MConstants.WETH9
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
        if (TARGET_SWAP_POOL != address(0)) setSwapAdapterToV3SingleSwap(TARGET_SWAP_POOL);
        _setComponents(address(rebalanceAdapter));
        rebalanceAdapter.setRebalanceOperator(deployer.addr);
        rebalanceAdapter.setLastRebalanceSnapshot(oracle.price(), initialSQRTPrice, 0);

        initPool(key.currency0, key.currency1, key.hooks, key.fee, key.tickSpacing, initialSQRTPrice);

        // This is needed in order to simulate proper accounting.
        deal(address(BASE), address(manager), 100000 ether);
        deal(address(QUOTE), address(manager), 100000 ether);

        quoter = new V4Quoter(manager);
        vm.stopPrank();
    }

    function approve_accounts() public virtual override {
        super.approve_accounts();

        vm.startPrank(swapper.addr);
        BASE.forceApprove(address(swapRouter), type(uint256).max);
        QUOTE.forceApprove(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(marketMaker.addr);
        BASE.forceApprove(address(MConstants.UNISWAP_V3_ROUTER), type(uint256).max);
        QUOTE.forceApprove(address(MConstants.UNISWAP_V3_ROUTER), type(uint256).max);
        vm.stopPrank();
    }
}
