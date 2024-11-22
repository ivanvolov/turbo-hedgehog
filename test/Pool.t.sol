// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ISwapRouter} from "@forks/ISwapRouter.sol";
import {IUniswapV3Pool} from "@forks/IUniswapV3Pool.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {TestERC20} from "v4-core/test/TestERC20.sol";

contract PoolTest is Test {
    using TestAccountLib for TestAccount;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    TestAccount alice;
    TestAccount lender;
    TestERC20 USDC;
    TestERC20 WETH;
    TestERC20 USDT;

    uint256 startBlock = 21130276;
    uint256 skipBlocks = 10;

    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        lender = TestAccountLib.createTestAccount("lender");

        WETH = TestERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vm.label(address(WETH), "WETH");
        USDC = TestERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        vm.label(address(USDC), "USDC");
        USDT = TestERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        vm.label(address(USDT), "USDT");
    }

    function test_new_ALM_concept1() public {
        _ALM_concept(startBlock);
    }

    function test_new_ALM_concept2() public {
        _ALM_concept(startBlock + skipBlocks);
    }

    function test_new_ALM_concept3() public {
        _ALM_concept(startBlock + skipBlocks * 2);
    }

    function _ALM_concept(uint256 blockNumber) public {
        vm.rollFork(blockNumber);

        alice = TestAccountLib.createTestAccount("alice");
        vm.startPrank(alice.addr);

        // USDT.approve(SWAP_ROUTER, 1);
        // USDT.approve(SWAP_ROUTER, type(uint256).max);
        USDC.approve(SWAP_ROUTER, type(uint256).max);
        WETH.approve(SWAP_ROUTER, type(uint256).max);

        // ** Airdrop WETH to user
        uint256 initialAmount = 10 ether;
        deal(address(WETH), alice.addr, initialAmount);
        console.log("Initial WETH balance", WETH.balanceOf(alice.addr));

        // ** Swap WETH to USDT
        swapExactInput(address(WETH), address(USDT), initialAmount);
        console.log("USDT balance after swap", USDT.balanceOf(alice.addr));

        // ** Emulate borrowing USDC for USDT
        deal(address(USDC), alice.addr, USDT.balanceOf(alice.addr));
        // USDT.transfer(SWAP_ROUTER, USDT.balanceOf(alice.addr));
        // console.log("USDT balance after borrow", USDT.balanceOf(alice.addr));
        console.log("USDC balance after borrow", USDC.balanceOf(alice.addr));

        swapExactInput(
            address(USDC),
            address(WETH),
            USDC.balanceOf(alice.addr)
        );
        console.log("WETH balance after swap", WETH.balanceOf(alice.addr));
        vm.stopPrank();
    }

    address wethUSDCPool = 0x11b815efB8f581194ae79006d24E0d814B7697F6;
    address usdcWETHPool = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    uint24 feeFor005Swap = 500;
    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter constant swapRouter = ISwapRouter(SWAP_ROUTER);

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256) {
        // console.log("Swapping", USDC.allowance(alice.addr, SWAP_ROUTER));
        // console.log("Swapping", USDC.balanceOf(alice.addr));
        return
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: feeFor005Swap,
                    recipient: alice.addr,
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
    }
}
