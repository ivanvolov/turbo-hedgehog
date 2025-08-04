# These are notes about how often one swap path is common for different routes.

swapExactOutput_V4_SINGLE_BASE_QUOTE
swapExactInput_V4_SINGLE_BASE_QUOTE {
abi.encode(poolKeyUSDC_USDT, true, bytes(""))
}

swapExactOutput_V4_SINGLE_QUOTE_BASE
swapExactInput_V4_SINGLE_QUOTE_BASE {
abi.encode(poolKeyUSDC_USDT, false, bytes(""))
}

swapExactInput_V4_MULTIHOP_BASE_QUOTE {
path[0] = PathKey(poolKeyETH_USDC.currency0);
path[1] = PathKey(poolKeyETH_USDT.currency1);
}

swapExactOutput_V4_MULTIHOP_BASE_QUOTE {
path[0] = PathKey(poolKeyETH_USDC.currency1);
path[1] = PathKey(poolKeyETH_USDT.currency0);
}

swapExactInput_V4_MULTIHOP_QUOTE_BASE {
path[0] = PathKey(poolKeyETH_USDT.currency0);
path[1] = PathKey(poolKeyETH_USDC.currency1);
}

swapExactOutput_V4_MULTIHOP_QUOTE_BASE {
path[0] = PathKey(poolKeyETH_USDT.currency1);
path[1] = PathKey(poolKeyETH_USDC.currency0);
}

swapExactOutput_V3_SINGLE_QUOTE_BASE
swapExactInput_V3_SINGLE_BASE_QUOTE {
abi.encodePacked(TestLib.USDC, uint24(fee), TestLib.USDT);
}

swapExactInput_V3_SINGLE_QUOTE_BASE
swapExactOutput_V3_SINGLE_BASE_QUOTE {
abi.encodePacked(TestLib.USDT, uint24(fee), TestLib.USDC);
}

swapExactOutput_V3_MULTIHOP_QUOTE_BASE
swapExactInput_V3_MULTIHOP_BASE_QUOTE {
abi.encodePacked(
TestLib.USDC,
uint24(IUniswapV3Pool(TestLib.uniswap_v3_USDC_WETH\_\_POOL).fee()),
address(TestLib.WETH),
uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDT_POOL).fee()),
TestLib.USDT
);
}

swapExactInput_V3_MULTIHOP_QUOTE_BASE
swapExactOutput_V3_MULTIHOP_BASE_QUOTE {
abi.encodePacked(
TestLib.USDT,
uint24(IUniswapV3Pool(TestLib.uniswap_v3_WETH_USDT_POOL).fee()),
address(TestLib.WETH),
uint24(IUniswapV3Pool(TestLib.uniswap_v3_USDC_WETH\_\_POOL).fee()),
TestLib.USDC
);
}

swapExactOutput_V2_SINGLE_BASE_QUOTE
swapExactInput_V2_SINGLE_BASE_QUOTE {
path[0] = TestLib.USDC;
path[1] = TestLib.USDT;
}

swapExactOutput_V2_SINGLE_QUOTE_BASE
swapExactInput_V2_SINGLE_QUOTE_BASE {
path[0] = TestLib.USDT;
path[1] = TestLib.USDC;
}

swapExactOutput_V2_MULTIHOP_BASE_QUOTE
swapExactInput_V2_MULTIHOP_BASE_QUOTE {
path[0] = TestLib.USDC;
path[1] = TestLib.WETH;
path[2] = TestLib.USDT;
}

swapExactOutput_V2_MULTIHOP_QUOTE_BASE
swapExactInput_V2_MULTIHOP_QUOTE_BASE {
path[0] = TestLib.USDT;
path[1] = TestLib.WETH;
path[2] = TestLib.USDC;
}

# These are notes about how mixed paths swap performs compared to a single path swap.

ProtocolType.V2 => 998474274
ProtocolType.V3 => 1000192674
ProtocolType.V4_SINGLE => 1000176859
ProtocolType.V4_MULTIHOP => 999107408
0.25% mix => 999639259
