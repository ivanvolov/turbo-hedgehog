build:
	clear && forge clean && forge build

ta:
	clear && forge test -v --no-match-contract "SimulationTest"

tam:
	clear && forge test -v --no-match-contract "Simulation|UNI|OracleTest|LendingAdaptersTest"

tau:
	clear && forge test -v --match-contract "UNI_ALMTest"

ts:
	clear && forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_simulation --ffi
tsl:
	clear && forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_simulation --ffi

trs:
	clear && forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_rebalance_simulation --ffi
trsl:
	clear && forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_rebalance_simulation --ffi

tss:
	clear && forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_swaps_simulation --ffi
tssl:
	clear && forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_swaps_simulation --ffi

teu:
	clear && forge test -vv --match-contract ETH_UNICORD_ALMTest --match-test "test_"
teul:
	clear && forge test -vvvv --match-contract ETH_UNICORD_ALMTest --match-test "test_"

te:
	clear && forge test -vv --match-contract ETH_ALMTest --match-test "test_"
tel:
	clear && forge test -vvvv --match-contract ETH_ALMTest --match-test "test_"

ten:
	clear && forge test -vv --match-contract ETH_Native_ALMTest --match-test "test_lifecycle"
tenl:
	clear && forge test -vvvv --match-contract ETH_Native_ALMTest --match-test "test_lifecycle"

ter:
	clear && forge test -vv --match-contract ETH_R_ALMTest --match-test "test_"
terl:
	clear && forge test -vvvv --match-contract ETH_R_ALMTest --match-test "test_"

tern:
	clear && forge test -vv --match-contract ETH_R_UNI_ALMTest --match-test "test_"
ternl:
	clear && forge test -vvvv --match-contract ETH_R_UNI_ALMTest --match-test "test_"

ter2n:
	clear && forge test -vv --match-contract ETH_R2_UNI_ALMTest --match-test "test_"
tern2l:
	clear && forge test -vvvv --match-contract ETH_R2_UNI_ALMTest --match-test "test_"

ter2:
	clear && forge test -vv --match-contract ETH_R2_ALMTest --match-test "test_"
ter2l:
	clear && forge test -vvvv --match-contract ETH_R2_ALMTest --match-test "test_"

tu:
	clear && forge test -vv --match-contract UNICORD_ALMTest --match-test "test_"
tul:
	clear && forge test -vvvv --match-contract UNICORD_ALMTest --match-test "test_"

tur:
	clear && forge test -vv --match-contract UNICORD_R_ALMTest --match-test "test_"
turl:
	clear && forge test -vvvv --match-contract UNICORD_R_ALMTest --match-test "test_"

tb:
	clear && forge test -vv --match-contract BTC_ALMTest --match-test "test_"
tbl:
	clear && forge test -vvvv --match-contract BTC_ALMTest --match-test "test_"

td:
	clear && forge test -vv --match-contract DeltaNeutral_ALMTest --match-test "test_"
tdl:
	clear && forge test -vvvv --match-contract DeltaNeutral_ALMTest --match-test "test_"

tdu:
	clear && forge test -vv --match-contract DeltaNeutral_UNI_ALMTest --match-test "test_"
tdul:
	clear && forge test -vvvv --match-contract DeltaNeutral_UNI_ALMTest --match-test "test_"

tg:
	clear && forge test -vv --match-contract General_ALMTest --match-test "test_"
tgl:
	clear && forge test -vvvv --match-contract General_ALMTest --match-test "test_"

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
	clear && forge test -vv --match-contract "ETH_ALMTest\b" --match-test "test_lifecycle"
gas_s:
	clear && forge snapshot --match-contract "ETH_ALMTest\b" --match-test "test_lifecycle"

merkl_data:
	clear && npm run merkl
morpho_data:
	clear && npm run morpho
init_pool_events:
	clear && npm run init_pool_events
