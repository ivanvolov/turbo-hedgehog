// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// ** Morpho imports
import {IMorpho, Id, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IMorphoChainlinkOracleV2Factory} from "@forks/morpho-oracles/IMorphoChainlinkOracleV2Factory.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {MorphoLendingAdapter} from "@src/core/lendingAdapters/MorphoLendingAdapter.sol";

// ** libraries
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {TestLib} from "@test/libraries/TestLib.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

abstract contract MorphoTestBase is ALMTestBase {
    using TestAccountLib for TestAccount;
    using SafeERC20 for IERC20;

    TestAccount marketCreator;
    TestAccount morphoLpProvider;

    Id shortMId;
    Id longMId;
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    IMorphoChainlinkOracleV2Factory oracleFactory =
        IMorphoChainlinkOracleV2Factory(0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766);

    function create_lending_adapter_morpho() internal {
        create_and_seed_morpho_markets();
        vm.prank(deployer.addr);
        lendingAdapter = new MorphoLendingAdapter(longMId, shortMId);
    }

    function create_lending_adapter_morpho_unicord() internal {
        create_and_seed_morpho_markets_unicord();
        vm.prank(deployer.addr);
        lendingAdapter = new MorphoLendingAdapter(longMId, shortMId);
    }

    function create_accounts_and_tokens(
        address _base,
        uint8 _bDec,
        string memory _baseName,
        address _quote,
        uint8 _qDec,
        string memory _quoteName
    ) public override {
        super.create_accounts_and_tokens(_base, _bDec, _baseName, _quote, _qDec, _quoteName);

        marketCreator = TestAccountLib.createTestAccount("marketCreator");
        morphoLpProvider = TestAccountLib.createTestAccount("morphoLpProvider");
    }

    function approve_accounts() public override {
        super.approve_accounts();
        vm.startPrank(alice.addr);
        BASE.forceApprove(address(morpho), type(uint256).max);
        QUOTE.forceApprove(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    function create_and_seed_morpho_markets() internal {
        longMId = create_morpho_market(
            address(BASE),
            address(QUOTE),
            915000000000000000,
            deployMockOracle(address(0), 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46, 18, 6)
        );
        provideLiquidityToMorpho(longMId, 4000000e6); // Providing some BASE

        shortMId = create_morpho_market(
            address(QUOTE),
            address(BASE),
            945000000000000000,
            deployMockOracle(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46, address(0), 6, 18)
        );
        provideLiquidityToMorpho(shortMId, 1000 ether); // Providing some QUOTE
    }

    function create_and_seed_morpho_markets_unicord() internal {
        longMId = create_morpho_market(
            address(BASE),
            address(QUOTE),
            915000000000000000,
            deployMockOracle(address(0), 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46, 18, 6)
        );
        provideLiquidityToMorpho(longMId, 4000000e6); // Providing some BASE

        shortMId = create_morpho_market(
            address(QUOTE),
            address(BASE),
            945000000000000000,
            deployMockOracle(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46, address(0), 6, 18)
        );
        provideLiquidityToMorpho(shortMId, 1000 ether); // Providing some QUOTE
    }

    function deployMockOracle(
        address feed0,
        address feed1,
        uint256 decimal0,
        uint256 decimal1
    ) internal returns (address) {
        address oracle = oracleFactory.createMorphoChainlinkOracleV2(
            address(0),
            1,
            AggregatorV3Interface(feed0),
            AggregatorV3Interface(address(0)),
            decimal0,
            address(0),
            1,
            AggregatorV3Interface(feed1),
            AggregatorV3Interface(address(0)),
            decimal1,
            bytes32(0)
        );

        return oracle;
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

    function provideLiquidityToMorpho(Id marketId, uint256 amount) internal {
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);

        vm.startPrank(morphoLpProvider.addr);
        deal(marketParams.loanToken, morphoLpProvider.addr, amount);

        IERC20(marketParams.loanToken).forceApprove(address(morpho), type(uint256).max);
        morpho.supply(marketParams, amount, 0, morphoLpProvider.addr, "");

        assertEqBalanceStateZero(morphoLpProvider.addr);
        vm.stopPrank();
    }
}
