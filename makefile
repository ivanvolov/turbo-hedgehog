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

te:
	clear && forge test -vv --match-contract ETHALMTest --match-test "test_lifecycle"
tel:
	clear && forge test -vvvv --match-contract ETHALMTest --match-test "test_lifecycle"
tb:
	clear && forge test -vv --match-contract BTCALMTest --match-test "test_lifecycle"
tbl:
	clear && forge test -vvvv --match-contract BTCALMTest --match-test "test_lifecycle"
td:
	clear && forge test -vv --match-contract DeltaNeutralALMTest --match-test "test_"
tdl:
	clear && forge test -vvvv --match-contract DeltaNeutralALMTest --match-test "test_"

tg:
	clear && forge test -vv --match-contract ALMGeneralTest --match-test "test_"
tgl:
	clear && forge test -vvvv --match-contract ALMGeneralTest --match-test "test_"

spell:
	clear && cspell "**/*.*"