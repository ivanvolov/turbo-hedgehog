ta:
	clear && forge test -vv

ts:
	clear && forge test -vv --match-contract ETHALMSimulationTest --match-test test_simulation --ffi
tsl:
	clear && forge test -vvvv --match-contract ETHALMSimulationTest --match-test test_simulation --ffi

trs:
	clear && forge test -vv --match-contract ETHALMSimulationTest --match-test test_rebalance_simulation --ffi
trsl:
	clear && forge test -vvvv --match-contract ETHALMSimulationTest --match-test test_rebalance_simulation --ffi

t:
	clear && forge test -vv --match-contract ETHALMTest --match-test "test_deposit_rebalance_swap_rebalance"
tl:
	clear && forge test -vvvv --match-contract ETHALMTest --match-test "test_deposit_rebalance_swap_rebalance"
tg:
	clear && forge test -vv --match-contract ALMGeneralTest --match-test "test_"


spell:
	clear && cspell "**/*.*"