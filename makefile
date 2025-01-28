ta:
	clear && forge test -vv --no-match-contract "SimulationTest"

ts:
	clear && forge test -vv --match-contract ETHALMSimulationTest --match-test test_simulation --ffi
tsl:
	clear && forge test -vvvv --match-contract ETHALMSimulationTest --match-test test_simulation --ffi

trs:
	clear && forge test -vv --match-contract ETHALMSimulationTest --match-test test_rebalance_simulation --ffi
trsl:
	clear && forge test -vvvv --match-contract ETHALMSimulationTest --match-test test_rebalance_simulation --ffi

tss:
	clear && forge test -vv --match-contract ETHALMSimulationTest --match-test test_swaps_simulation --ffi
tssl:
	clear && forge test -vvvv --match-contract ETHALMSimulationTest --match-test test_swaps_simulation --ffi

t:
	clear && forge test -vv --match-contract ETHALMTest --match-test "test_"
tl:
	clear && forge test -vvvv --match-contract ETHALMTest --match-test "test_"
t2:
	clear && forge test -vv --match-contract DeltaNeutralALMTest --match-test "test_"
t2l:
	clear && forge test -vvvv --match-contract DeltaNeutralALMTest --match-test "test_"
tg:
	clear && forge test -vv --match-contract ALMGeneralTest --match-test "test_"


spell:
	clear && cspell "**/*.*"