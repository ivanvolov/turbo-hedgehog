// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

// ** contracts
import {ALMTestBase} from "@test/core/ALMTestBase.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IOracleTest, IChronicleSelfKisser} from "@test/interfaces/IOracleTest.sol";

contract OracleTest is ALMTestBase {
    using SafeERC20 for IERC20;

    function setUp() public {
        _select_mainnet_fork(22375550);
    }

    function test_strategy_oracles_chainlink() public {
        IOracle mock_oracle;

        console.log("> DN/ETHALM");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDC,
                25 hours,
                25 hours,
                true,
                int8(6 - 18)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            // Human readable oraclePrice: 1817030479873254341041
            assertEq(price, 1817030479);
            // assertEq(sqrtPrice, 550348500785935357994619527);
        }

        console.log("> ETH-R-ALM/ETH-R2-ALM");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_WETH,
                MConstants.chainlink_feed_USDT,
                1 hours,
                10 hours,
                false,
                int8(6 - 18)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            // Human readable oraclePrice: 1816422855463561861669
            assertEq(price, 1816422855);
            // assertEq(sqrtPrice, 1816422855);
        }

        console.log("> BTC_ALMTest");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_CBBTC,
                MConstants.chainlink_feed_USDC,
                10 hours,
                10 hours,
                true,
                int8(6 - 8)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            // Human readable oraclePrice: 95041476087981443534362
            assertEq(price, 950414760879814435343);
            // assertEq(sqrtPrice, 1052172210661252);
        }

        // This example is not present in strategies
        {
            // mock_oracle = _create_oracle(MConstants.chainlink_feed_USDC, MConstants.chainlink_feed_CBBTC, 50 hours, 50 hours);
            // console.log("oracle", mock_oracle.price());
        }

        console.log("> UNICORD-R");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_DAI,
                MConstants.chainlink_feed_USDC,
                10 hours,
                10 hours,
                true,
                int8(0)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 1000217771097615134);
            // assertEq(sqrtPrice, 999782276316310439);
        }

        console.log("> UNICORD");
        {
            mock_oracle = _create_oracle(
                MConstants.chainlink_feed_USDT,
                MConstants.chainlink_feed_USDC,
                10 hours,
                10 hours,
                true,
                int8(0)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 1000334517046988714);
            // assertEq(sqrtPrice, 999665594817245518);
        }
    }

    /// Api3 Market only offers a 24-hour heartbeat interval.
    /// It is important to buy price feeds yourself because deviation thresholds can be updated - we have a vulnerability here.
    /// See plans and durations for more update functionality: https://docs.api3.org/dapps/integration/#plan-durations.
    /// Look into gas grants, they can purchase plans for you: https://docs.api3.org/dapps/integration/#gas-grants.
    function test_strategy_oracles_api3() public {
        IOracle mock_oracle;
        _select_mainnet_fork(22974236);

        console.log("> DN/ETHALM");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473), // WETH
                AggregatorV3Interface(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f), // USDC
                24 hours,
                24 hours,
                true,
                int8(6 - 18)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 3635798239);
            // assertEq(sqrtPrice, 275042764824882792402936746);
        }

        console.log("> ETH-R-ALM/ETH-R2-ALM");
        {
            _select_arbitrum_fork(360360800);
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473), // WETH
                AggregatorV3Interface(0x4eadC6ee74b7Ceb09A4ad90a33eA2915fbefcf76), // USDT
                24 hours,
                24 hours,
                false,
                int8(6 - 18)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 3683777823);
            // assertEq(sqrtPrice, 3683777823);
        }

        console.log("> BTC_ALMTest");
        {
            _select_sepolia_fork(8817967);
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0xa4183Cbf2eE868dDFccd325531C4f53F737FFF68), // CBBTC
                AggregatorV3Interface(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f), // USDC
                24 hours,
                24 hours,
                true,
                int8(6 - 8)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 1193629881221990642759);
            // assertEq(sqrtPrice, 837780635129743);
        }

        // This example is not present in strategies
        {
            // mock_oracle = _create_oracle(MConstants.chainlink_feed_USDC, MConstants.chainlink_feed_CBBTC, 24 hours, 24 hours);
            // console.log("oracle", mock_oracle.price());
        }

        console.log("> UNICORD-R");
        {
            _select_sepolia_fork(8818009);
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x85b6dD270538325A9E0140bd6052Da4ecc18A85c), //DAI
                AggregatorV3Interface(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f), // USDC
                24 hours,
                24 hours,
                true,
                int8(0)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 1000207563825876356);
            // assertEq(sqrtPrice, 999792479247924893);
        }

        console.log("> UNICORD");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x4eadC6ee74b7Ceb09A4ad90a33eA2915fbefcf76), // USDT
                AggregatorV3Interface(0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f), // USDC
                24 hours,
                24 hours,
                true,
                int8(0)
            );

            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 1000849189697260507);
            // assertEq(sqrtPrice, 999151530814030661);
        }
    }

    function test_strategy_oracles_chronicle() public {
        IOracle mock_oracle;
        _select_sepolia_fork(8818766);

        console.log("> DN/ETHALM");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x3b8Cd6127a6CBEB9336667A3FfCD32B3509Cb5D9), // WETH
                AggregatorV3Interface(0xb34d784dc8E7cD240Fe1F318e282dFdD13C389AC), // USDC
                24 hours,
                24 hours,
                true,
                int8(6 - 18)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 3646184618);
            // assertEq(sqrtPrice, 274259288754423679596577136);
        }

        console.log("> ETH-R-ALM/ETH-R2-ALM");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x3b8Cd6127a6CBEB9336667A3FfCD32B3509Cb5D9), // WETH
                AggregatorV3Interface(0x8c852EEC6ae356FeDf5d7b824E254f7d94Ac6824), // USDT
                24 hours,
                24 hours,
                false,
                int8(6 - 18)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 3644507977);
            // assertEq(sqrtPrice, 3644507977);
        }

        console.log("> BTC_ALMTest");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0xe4f05C62c09a3ec000a3f3895eFD2Ec9a1A11742), // CBBTC
                AggregatorV3Interface(0xb34d784dc8E7cD240Fe1F318e282dFdD13C389AC), // USDC
                24 hours,
                24 hours,
                true,
                int8(6 - 8)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 1190799525762077236252);
            // assertEq(sqrtPrice, 839771916570111);
        }

        // This example is not present in strategies
        {
            // mock_oracle = _create_oracle(MConstants.chainlink_feed_USDC, MConstants.chainlink_feed_CBBTC, 24 hours, 24 hours);
            // console.log("oracle", mock_oracle.price());
        }

        console.log("> UNICORD-R");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0xaf900d10f197762794C41dac395C5b8112eD13E1), //DAI
                AggregatorV3Interface(0xb34d784dc8E7cD240Fe1F318e282dFdD13C389AC), // USDC
                24 hours,
                24 hours,
                true,
                int8(0)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 999979154161890803);
            // assertEq(sqrtPrice, 1000020846272667222);
        }

        console.log("> UNICORD");
        {
            mock_oracle = _create_oracle(
                AggregatorV3Interface(0x8c852EEC6ae356FeDf5d7b824E254f7d94Ac6824), // USDT
                AggregatorV3Interface(0xb34d784dc8E7cD240Fe1F318e282dFdD13C389AC), // USDC
                24 hours,
                24 hours,
                true,
                int8(0)
            );

            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedQuote()), mock_oracle);
            whitelist_chronicle_feed(address(IOracleTest(address(mock_oracle)).feedBase()), mock_oracle);
            (uint256 price, ) = mock_oracle.poolPrice();
            assertEq(price, 1000460046004600460);
            // assertEq(sqrtPrice, 999540165540405454);
        }
    }

    // ** Helpers

    function _select_mainnet_fork(uint256 block_number) internal {
        select_mainnet_fork(block_number);
        _create_accounts();
    }

    function _select_arbitrum_fork(uint256 block_number) internal {
        select_arbitrum_fork(block_number);
        _create_accounts();
    }

    function _select_sepolia_fork(uint256 block_number) internal {
        select_sepolia_fork(block_number);
        _create_accounts();
    }

    function whitelist_chronicle_feed(address feed, IOracle _oracle) internal {
        vm.prank(deployer.addr);
        IChronicleSelfKisser(0x9eE458DefDc50409DbF153515DA54Ff5B744e533).selfKiss(feed, address(_oracle));
    }
}
