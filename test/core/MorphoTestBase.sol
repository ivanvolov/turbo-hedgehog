// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// ** Morpho imports
import {MarketParamsLib} from "@forks/morpho/libraries/MarketParamsLib.sol";
import {IChainlinkOracle} from "@forks/morpho-oracles/IChainlinkOracle.sol";
import {IMorpho, MarketParams, Position as MorphoPosition, Id} from "@forks/morpho/IMorpho.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** libraries
import {TestERC20} from "v4-core/test/TestERC20.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";

abstract contract MorphoTestBase is ALMTestBase {
    using TestAccountLib for TestAccount;

    TestAccount marketCreator;
    TestAccount morphoLpProvider;

    Id shortMId;
    Id longMId;
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    function create_accounts_and_tokens() public override {
        super.create_accounts_and_tokens();

        marketCreator = TestAccountLib.createTestAccount("marketCreator");
        morphoLpProvider = TestAccountLib.createTestAccount("morphoLpProvider");
    }

    function approve_accounts() public override {
        super.approve_accounts();
        vm.startPrank(alice.addr);
        USDC.approve(address(morpho), type(uint256).max);
        WETH.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    function create_and_seed_morpho_markets() internal {
        address _oracle = 0x48F7E36EB6B826B2dF4B2E630B62Cd25e89E40e2;

        // @Notice: The price rate of 1 asset of collateral token quoted in 1 asset of loan token. With `36 + loan token decimals - collateral token decimals` decimals.
        // modifyMockOracle(_oracle, 4487851340816804029821232973); //4487 usdc for eth
        modifyMockOracle(_oracle, 222866057499442861561321795465945421627523072); //4487 usdc for eth, reversed _oracle

        longMId = create_morpho_market(address(USDC), address(WETH), 915000000000000000, _oracle);
        provideLiquidityToMorpho(longMId, 1000 ether); // Providing some ETH

        shortMId = create_morpho_market(address(WETH), address(USDC), 945000000000000000, _oracle);
        provideLiquidityToMorpho(shortMId, 4000000 * 1e6); // Providing some USDC
    }

    function create_morpho_market(
        address loanToken,
        address collateralToken,
        uint256 lltv,
        address _oracle
    ) internal returns (Id) {
        MarketParams memory marketParams = MarketParams(
            loanToken,
            collateralToken,
            _oracle,
            0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, // We have only 1 irm in morpho so we can use this address
            lltv
        );

        vm.prank(marketCreator.addr);
        morpho.createMarket(marketParams);
        return MarketParamsLib.id(marketParams);
    }

    function modifyMockOracle(address _oracle, uint256 newPrice) internal returns (IChainlinkOracle iface) {
        //NOTICE: https://github.com/morpho-org/morpho-blue-oracles
        iface = IChainlinkOracle(_oracle);

        vm.mockCall(address(_oracle), abi.encodeWithSelector(iface.price.selector), abi.encode(newPrice));
        return iface;
    }

    function provideLiquidityToMorpho(Id marketId, uint256 amount) internal {
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);

        vm.startPrank(morphoLpProvider.addr);
        deal(marketParams.loanToken, morphoLpProvider.addr, amount);

        TestERC20(marketParams.loanToken).approve(address(morpho), type(uint256).max);
        (, uint256 shares) = morpho.supply(marketParams, amount, 0, morphoLpProvider.addr, "");

        assertEqMorphoS(marketId, morphoLpProvider.addr, shares, 0, 0);
        assertEqBalanceStateZero(morphoLpProvider.addr);
        vm.stopPrank();
    }

    // -- Custom assertions -- //

    function assertEqMorphoS(
        Id marketId,
        uint256 _supplyShares,
        uint256 _borrowShares,
        uint256 _collateral
    ) public view {
        assertEqMorphoS(marketId, address(lendingAdapter), _supplyShares, _borrowShares, _collateral);
    }

    function assertEqMorphoS(
        Id marketId,
        address owner,
        uint256 _supplyShares,
        uint256 _borrowShares,
        uint256 _collateral
    ) public view {
        MorphoPosition memory p;
        p = morpho.position(marketId, owner);
        assertApproxEqAbs(p.supplyShares, _supplyShares, 10, "supply shares not equal");
        assertApproxEqAbs(p.borrowShares, _borrowShares, 10, "borrow shares not equal");
        assertApproxEqAbs(p.collateral, _collateral, 10000, "collateral not equal");
    }

    function assertEqMorphoA(
        Id marketId,
        uint256 _suppliedAssets,
        uint256 _borrowAssets,
        uint256 _collateral
    ) public view {
        assertEqMorphoA(marketId, address(lendingAdapter), _suppliedAssets, _borrowAssets, _collateral);
    }

    function assertEqMorphoA(
        Id marketId,
        address owner,
        uint256 _suppliedAssets,
        uint256 _borrowAssets,
        uint256 _collateral
    ) public view {
        MorphoPosition memory p;
        p = morpho.position(marketId, owner);

        assertApproxEqAbs(
            MorphoBalancesLib.expectedSupplyAssets(morpho, morpho.idToMarketParams(marketId), owner),
            _suppliedAssets,
            10,
            "supply assets not equal"
        );
        assertApproxEqAbs(
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(marketId), owner),
            _borrowAssets,
            10,
            "borrow assets not equal"
        );
        assertApproxEqAbs(p.collateral, _collateral, 10000, "collateral not equal");
    }
}
