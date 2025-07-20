build:
	clear && forge clean && forge build

ta:
	clear && forge test -vv --no-match-contract "SimulationTest|ETHR2ALMTest|UNICORDRALMTest"

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
	clear && forge test -vv --match-contract ETHALMTest --match-test "test_"
tel:
	clear && forge test -vvvv --match-contract ETHALMTest --match-test "test_deposit_rebalance_swap_price_up_in_fees\b"
ter:
	clear && forge test -vv --match-contract ETHRALMTest --match-test "test_"
terl:
	clear && forge test -vvvv --match-contract ETHRALMTest --match-test "test_"


tu:
	clear && forge test -vv --match-contract UNICORDALMTest --match-test "test_"
tul:
	clear && forge test -vvvv --match-contract UNICORDALMTest --match-test "test_"

tur:
	clear && forge test -vv --match-contract UNICORDRALMTest --match-test "test_"
turl:
	clear && forge test -vvvv --match-contract UNICORDRALMTest --match-test "test_"

tb:
	clear && forge test -vv --match-contract BTCALMTest --match-test "test_"
tbl:
	clear && forge test -vvvv --match-contract BTCALMTest --match-test "test_"
td:
	clear && forge test -vv --match-contract DeltaNeutralALMTest --match-test "test_deposit_rebalance\b"
tdl:
	clear && forge test -vvvv --match-contract DeltaNeutralALMTest --match-test "test_deposit_rebalance\b"

tg:
	clear && forge test -vv --match-contract ALMGeneralTest --match-test "test_"
tgl:
	clear && forge test -vvvv --match-contract ALMGeneralTest --match-test "test_"
tla:
	clear && forge test -vv --match-contract LendingAdaptersTest --match-test "test_"
tlal:
	clear && forge test -vvvv --match-contract LendingAdaptersTest --match-test "test_"
tra:
	clear && forge test -vv --match-contract RewardsAdaptersTest --match-test "test_"
tral:
	clear && forge test -vvvv --match-contract RewardsAdaptersTest --match-test "test_"
tsa:
	clear && forge test -vv --match-contract SwapAdapterTest --match-test "test_"
tsal:
	clear && forge test -vvvv --match-contract SwapAdapterTest --match-test "test_"
to:
	clear && forge test -vv --match-contract OracleTest --match-test "test_"
tol:
	clear && forge test -vvvv --match-contract OracleTest --match-test "test_"

format:
	npx prettier --check "src/**/*.sol" "test/**/*.sol"
format_write:
	npx prettier --write "src/**/*.sol" "test/**/*.sol"

gas_r:
	clear && forge test -vv --match-contract "ETHALMTest\b" --match-test "test_lifecycle\b"
gas_s:
	clear && forge snapshot --match-contract "ETHALMTest\b" --match-test "test_lifecycle"

merkl_data:
	clear && npm run merkl
morpho_data:
	clear && npm run morpho
init_pool_events:
	clear && npm run init_pool_events
