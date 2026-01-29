// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** Morpho imports
import {IMorpho, Id, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IMorphoChainlinkOracleV2Factory} from "@morpho-oracles/IMorphoChainlinkOracleV2Factory.sol";

// ** contracts
import {TestBaseEuler} from "./TestBaseEuler.sol";
import {MorphoLendingAdapter} from "@src/core/lendingAdapters/MorphoLendingAdapter.sol";
import {MorphoFlashLoanAdapter} from "@src/core/flashLoanAdapters/MorphoFlashLoanAdapter.sol";

// ** libraries
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";
import {Constants as UConstants} from "@test/libraries/constants/UnichainConstants.sol";
import {Constants as BConstants} from "@test/libraries/constants/BaseConstants.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ILendingAdapterMorpho} from "@test/interfaces/ILendingAdapterMorpho.sol";
import {IUniversalRewardsDistributor} from "@universal-rewards-distributor/IUniversalRewardsDistributor.sol";

abstract contract TestBaseMorpho is TestBaseEuler {
    using TestAccountLib for TestAccount;
    using SafeERC20 for IERC20;

    TestAccount marketCreator;
    TestAccount morphoLpProvider;

    Id shortMId;
    Id longMId;
    IMorpho morpho = MConstants.MORPHO;
    IMorphoChainlinkOracleV2Factory oracleFactory = MConstants.morphoOracleFactory;

    // --- Overrides --- //

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

    function approve_accounts() public virtual override {
        super.approve_accounts();

        vm.startPrank(alice.addr);
        BASE.forceApprove(address(morpho), type(uint256).max);
        QUOTE.forceApprove(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    // --- Shortcuts --- //

    function create_flash_loan_adapter_morpho() internal {
        vm.prank(deployer.addr);
        flashLoanAdapter = new MorphoFlashLoanAdapter(BASE, QUOTE, MConstants.MORPHO);
    }

    function create_flash_loan_adapter_morpho_unichain() internal {
        vm.prank(deployer.addr);
        flashLoanAdapter = new MorphoFlashLoanAdapter(BASE, QUOTE, UConstants.MORPHO);
    }

    function create_flash_loan_adapter_morpho_base() internal {
        vm.prank(deployer.addr);
        flashLoanAdapter = new MorphoFlashLoanAdapter(BASE, QUOTE, BConstants.MORPHO);
    }

    function create_lending_adapter_morpho_USDC_WETH_base() internal {
        {
            shortMId = Id.wrap(bytes32(0x3b3769cfca57be2eaed03fcc5299c25691b77781a1e124e7a8d520eb9a7eabb5));
            longMId = Id.wrap(bytes32(0x8793cf302b8ffd655ab97bd1c695dbd967807e8367a65cb2f4edaf1380ba1bda));
        }

        vm.prank(deployer.addr);
        lendingAdapter = new MorphoLendingAdapter(
            BASE,
            QUOTE,
            BConstants.MORPHO,
            longMId,
            shortMId,
            IERC4626(address(0)),
            IERC4626(address(0)),
            BConstants.merklRewardsDistributor
        );

        setURD(BConstants.universalRewardsDistributor);
    }

    function create_lending_adapter_morpho() internal {
        create_and_seed_morpho_markets();
        vm.prank(deployer.addr);
        IERC4626 mockAdapter = IERC4626(address(0));
        lendingAdapter = new MorphoLendingAdapter(
            BASE,
            QUOTE,
            MConstants.MORPHO,
            longMId,
            shortMId,
            mockAdapter,
            mockAdapter,
            MConstants.merklRewardsDistributor
        );

        setURD(MConstants.universalRewardsDistributor);
    }

    function create_lending_adapter_morpho_earn() internal {
        vm.prank(deployer.addr);
        lendingAdapter = new MorphoLendingAdapter(
            BASE,
            QUOTE,
            MConstants.MORPHO,
            Id.wrap(""),
            Id.wrap(""),
            MConstants.morphoUSDCVault,
            MConstants.morphoUSDTVault,
            MConstants.merklRewardsDistributor
        );

        setURD(MConstants.universalRewardsDistributor);
    }

    function create_lending_adapter_morpho_earn_USDC_USDT_unichain() internal {
        vm.prank(deployer.addr);
        lendingAdapter = new MorphoLendingAdapter(
            BASE,
            QUOTE,
            UConstants.MORPHO,
            Id.wrap(""),
            Id.wrap(""),
            UConstants.morphoUSDCVault,
            UConstants.morphoUSDTVault,
            UConstants.merklRewardsDistributor
        );

        // TODO: No rewards for unichain exists yet.
        // setURD(UConstants.universalRewardsDistributor);
    }

    function create_lending_adapter_morpho_earn_USDC_DAI() internal {
        vm.prank(deployer.addr);
        lendingAdapter = new MorphoLendingAdapter(
            BASE,
            QUOTE,
            MConstants.MORPHO,
            Id.wrap(""),
            Id.wrap(""),
            MConstants.morphoUSDCVault,
            MConstants.morphoDAIVault,
            MConstants.merklRewardsDistributor
        );

        setURD(MConstants.universalRewardsDistributor);
    }

    // --- Helpers --- //

    function setURD(IUniversalRewardsDistributor _universalRewardsDistributor) internal {
        vm.prank(deployer.addr);
        ILendingAdapterMorpho(address(lendingAdapter)).setURD(_universalRewardsDistributor);
    }

    function create_and_seed_morpho_markets() internal {
        longMId = _create_morpho_market(
            address(BASE),
            address(QUOTE),
            915000000000000000,
            _deployMockOracle(address(0), 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46, 18, 6)
        );
        _provideLiquidityToMorpho(longMId, 4000000e6); // Providing some BASE

        shortMId = _create_morpho_market(
            address(QUOTE),
            address(BASE),
            945000000000000000,
            _deployMockOracle(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46, address(0), 6, 18)
        );
        _provideLiquidityToMorpho(shortMId, 1000 ether); // Providing some QUOTE
    }

    function _deployMockOracle(
        address feed0,
        address feed1,
        uint256 decimal0,
        uint256 decimal1
    ) private returns (address) {
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

    function _create_morpho_market(
        address loanToken,
        address collateralToken,
        uint256 lltv,
        address _oracle
    ) private returns (Id) {
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

    function _provideLiquidityToMorpho(Id marketId, uint256 amount) private {
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);

        vm.startPrank(morphoLpProvider.addr);
        deal(marketParams.loanToken, morphoLpProvider.addr, amount);

        IERC20(marketParams.loanToken).forceApprove(address(morpho), type(uint256).max);
        morpho.supply(marketParams, amount, 0, morphoLpProvider.addr, "");

        assertEqBalanceStateZero(morphoLpProvider.addr);
        vm.stopPrank();
    }
}
