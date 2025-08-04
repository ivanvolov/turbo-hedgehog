// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** V4 imports
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

// ** contracts
import {TestBaseUniswap} from "./TestBaseUniswap.sol";
import {ALM} from "@src/ALM.sol";
import {Oracle} from "@src/core/oracles/Oracle.sol";

// ** libraries
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IBase} from "@src/interfaces/IBase.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

abstract contract TestBaseShortcuts is TestBaseUniswap {
    using TestAccountLib for TestAccount;
    using SafeERC20 for IERC20;

    // --- Shortcuts  --- //

    function deploy_hook_contract(bool _isInvertedAssets, IWETH9 WETH9) internal {
        address payable hookAddress = create_address_without_collision();
        (address currency0, address currency1) = getHookCurrenciesInOrder();

        key = PoolKey(
            Currency.wrap(currency0),
            Currency.wrap(currency1),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            1, // The value of tickSpacing doesn't change with dynamic fees, so it does matter.
            IHooks(hookAddress)
        );
        unauthorizedKey = PoolKey(key.currency0, key.currency1, LPFeeLibrary.DYNAMIC_FEE_FLAG, 2, IHooks(hookAddress));
        deployCodeTo(
            "ALM.sol",
            abi.encode(key, BASE, QUOTE, WETH9, isInvertedPool, _isInvertedAssets, isNTS, manager, "NAME", "SYMBOL"),
            hookAddress
        );
        hook = ALM(hookAddress);
        vm.label(address(hook), "hook");
    }

    function getHookCurrenciesInOrder() internal view returns (address currency0, address currency1) {
        (currency0, currency1) = (address(BASE), address(QUOTE));
        if (isNTS != 2) {
            if (currency0 == address(WETH9)) currency0 = address(ETH);
            if (currency1 == address(WETH9)) currency1 = address(ETH);
        }

        if (currency0 >= currency1) (currency0, currency1) = (currency1, currency0);

        console.log(">> key currency0: %s", currency0);
        console.log(">> key currency1: %s", currency1);
    }

    bool public deployedOnce = false;

    function create_address_without_collision() internal returns (address payable hookAddress) {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG
        );
        hookAddress = payable(deployedOnce ? address(flags ^ (0x4444 << 144)) : address(flags));
        deployedOnce = true;
    }

    function create_accounts_and_tokens(
        address _base,
        uint8 _bDec,
        string memory _baseName,
        address _quote,
        uint8 _qDec,
        string memory _quoteName
    ) public virtual {
        BASE = IERC20(_base);
        vm.label(_base, _baseName);
        QUOTE = IERC20(_quote);
        vm.label(_quote, _quoteName);
        baseName = _baseName;
        quoteName = _quoteName;
        bDec = _bDec;
        qDec = _qDec;

        _create_accounts();
    }

    function _create_accounts() internal {
        deployer = TestAccountLib.createTestAccount("deployer");
        alice = TestAccountLib.createTestAccount("alice");
        migrationContract = TestAccountLib.createTestAccount("migrationContract");
        swapper = TestAccountLib.createTestAccount("swapper");
        marketMaker = TestAccountLib.createTestAccount("marketMaker");
        zero = TestAccountLib.createTestAccount("zero");
        treasury = TestAccountLib.createTestAccount("treasury");
        mock_empty_oracle = TestAccountLib.createTestAccount("mock_empty_oracle");
    }

    function _setComponents(address module) internal {
        IBase(module).setComponents(
            hook,
            lendingAdapter,
            flashLoanAdapter,
            positionManager,
            oracle,
            rebalanceAdapter,
            swapAdapter
        );
    }

    function approve_accounts() public virtual {
        vm.startPrank(alice.addr);
        BASE.forceApprove(address(hook), type(uint256).max);
        QUOTE.forceApprove(address(hook), type(uint256).max);
        vm.stopPrank();
    }

    // --- Oracles  --- //

    function getFeedsData(AggregatorV3Interface feed) internal view returns (uint256 dec, uint256 price) {
        (, int256 _priceQuote, , uint256 updatedAtBase, ) = feed.latestRoundData();
        return (feed.decimals(), uint256(_priceQuote));
    }

    function create_oracle(
        bool _isInvertedPool,
        AggregatorV3Interface feedQ,
        AggregatorV3Interface feedB,
        uint128 stalenessThresholdQ,
        uint128 stalenessThresholdB
    ) internal returns (IOracle) {
        return
            _create_oracle(
                feedQ,
                feedB,
                stalenessThresholdQ,
                stalenessThresholdB,
                _isInvertedPool,
                int8(bDec) - int8(qDec)
            );
    }

    function _create_oracle(
        AggregatorV3Interface feedQ,
        AggregatorV3Interface feedB,
        uint128 stalenessThresholdQ,
        uint128 stalenessThresholdB,
        bool _isInvertedPool,
        int8 decimalsDelta
    ) internal returns (IOracle _oracle) {
        isInvertedPool = _isInvertedPool;
        vm.prank(deployer.addr);
        _oracle = new Oracle(feedB, feedQ, _isInvertedPool, decimalsDelta);
        oracle = _oracle;
        vm.prank(deployer.addr);
        oracle.setStalenessThresholds(stalenessThresholdB, stalenessThresholdQ);
    }

    function mock_latestRoundData(address feed, uint256 value) public {
        vm.mockCall(
            address(feed),
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(value), uint256(0), uint256(block.timestamp), uint80(0))
        );
    }

    function updateProtocolFees(uint256 _protocolFee) internal {
        (int24 lower, int24 upper) = hook.tickDeltas();
        hook.setProtocolParams(
            hook.liquidityMultiplier(),
            _protocolFee,
            hook.tvlCap(),
            lower,
            upper,
            hook.swapPriceThreshold()
        );
    }

    function updateProtocolTVLCap(uint256 _tvlCap) internal {
        (int24 lower, int24 upper) = hook.tickDeltas();
        hook.setProtocolParams(
            hook.liquidityMultiplier(),
            hook.protocolFee(),
            _tvlCap,
            lower,
            upper,
            hook.swapPriceThreshold()
        );
    }

    function updateProtocolPriceThreshold(uint256 _swapPriceThreshold) internal {
        (int24 lower, int24 upper) = hook.tickDeltas();
        hook.setProtocolParams(
            hook.liquidityMultiplier(),
            hook.protocolFee(),
            hook.tvlCap(),
            lower,
            upper,
            _swapPriceThreshold
        );
    }
}
