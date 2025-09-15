# Batches of tests

ta:
	clear && ./scripts/infisical_run.sh 'forge test -v --no-match-contract "SimulationTest"'

tam:
	clear && forge test -v --no-match-contract "Simulation|UNI_ALMTest|BASE_ALMTest|Oracle|LendingAdaptersTest"

tau:
	clear && forge test -v --match-contract "UNI_ALMTest|BASE_ALMTest"

# Strategies tests Mainnet

te:
	clear && forge test -vv --match-contract ETH_ALMTest --match-test "test_"
tel:
	clear && forge test -vvvv --match-contract ETH_ALMTest --match-test "test_"

ter:
	clear && forge test -vv --match-contract ETH_R_ALMTest --match-test "test_"
terl:
	clear && forge test -vvvv --match-contract ETH_R_ALMTest --match-test "test_"

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

tt:
	clear && forge test -vv --match-contract TURBO_ALMTest --match-test "test_"
ttl:
	clear && forge test -vvvv --match-contract TURBO_ALMTest --match-test "test_"


# Strategies tests Unichain

teuu:
	clear && forge test -vv --match-contract ETH_UNICORD_UNI_ALMTest --match-test "test_"
teuul:
	clear && forge test -vvvv --match-contract ETH_UNICORD_UNI_ALMTest --match-test "test_"

teu:
	clear && forge test -vv --match-contract ETH_UNI_ALMTest --match-test "test_"
teul:
	clear && forge test -vvvv --match-contract ETH_UNI_ALMTest --match-test "test_"

teru:
	clear && forge test -vv --match-contract ETH_R_UNI_ALMTest --match-test "test_"
terul:
	clear && forge test -vvvv --match-contract ETH_R_UNI_ALMTest --match-test "test_"

ter2u:
	clear && forge test -vv --match-contract ETH_R2_UNI_ALMTest --match-test "test_"
ter2ul:
	clear && forge test -vvvv --match-contract ETH_R2_UNI_ALMTest --match-test "test_"

tuu:
	clear && forge test -vv --match-contract UNICORD_UNI_ALMTest --match-test "test_"
tuul:
	clear && forge test -vvvv --match-contract UNICORD_UNI_ALMTest --match-test "test_"

turu:
	clear && forge test -vv --match-contract UNICORD_R_UNI_ALMTest --match-test "test_"
turul:
	clear && forge test -vvvv --match-contract UNICORD_R_UNI_ALMTest --match-test "test_"

tdu:
	clear && forge test -vv --match-contract DeltaNeutral_UNI_ALMTest --match-test "test_"
tdul:
	clear && forge test -vvvv --match-contract DeltaNeutral_UNI_ALMTest --match-test "test_"

# Strategies tests Base

tbb:
	clear && forge test -vv --match-contract BTC_BASE_ALMTest --match-test "test_"
tbbl:
	clear && forge test -vvvv --match-contract BTC_BASE_ALMTest --match-test "test_"

tdb:
	clear && forge test -vv --match-contract DeltaNeutral_R_BASE_ALMTest --match-test "test_"
tdbl:
	clear && forge test -vvvv --match-contract DeltaNeutral_R_BASE_ALMTest --match-test "test_"

# Adapters tests

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
	clear && forge test -vv --match-contract OracleFuzzing --match-test "test_Fuzz" --fuzz-runs 5000
tol:
	clear && forge test -vvvv --match-contract OracleFuzzing --match-test "test_Fuzz" --fuzz-runs 5000

tom:
	clear && forge test -vv --match-contract OracleMathTest --match-test "test_"
toml:
	clear && forge test -vvvv --match-contract OracleMathTest --match-test "test_"

# Simulations

tes:
	clear && forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_simulation --ffi
tesl:
	clear && forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_simulation --ffi

ters:
	clear && forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_rebalance_simulation --ffi
tersl:
	clear && forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_rebalance_simulation --ffi

tess:
	clear && forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_swaps_simulation --ffi
tessl:
	clear && forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_swaps_simulation --ffi

## Simulations oracles

deploy_test_contract:
	clear && forge script scripts/DeployOracleSimulation.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

get_data:
	clear && node --max-old-space-size=16384 --expose-gc test/simulations/oracleMath/anvilSim.s.js

viz_data:
	clear && python3 test/simulations/analytics/oracleFuzzing.py

# Maintenance scripts

build:
	clear && forge clean && forge build
builds:
	clear && forge clean && forge build --sizes

lint:
	clear && forge lint

format:
	npx prettier --check "src/**/*.sol" "test/**/*.sol"
format_write:
	npx prettier --write "src/**/*.sol" "test/**/*.sol"

merkl_data:
	clear && npm run merkl

morpho_data:
	clear && npm run morpho

init_pool_events:
	clear && npm run init_pool_events

# Gas reports

gas_r:
	clear && forge test -vv --match-contract "ETH_ALMTest\b" --match-test "test_lifecycle"
gas_s:
	clear && forge snapshot --match-contract "ETH_ALMTest\b" --match-test "test_lifecycle"

# Deploy anvil and simulate

deploy_on_anvil:
	clear && forge script scripts/Deploy.ALM.ANVIL.s.sol --broadcast --rpc-url http://127.0.0.1:8545

first_deposit_rebalance_anvil:
	clear && forge script scripts/anvil/FD_R.ALM.ANVIL.s.sol --broadcast --rpc-url http://127.0.0.1:8545

swap_anvil:
	clear && forge script scripts/anvil/SWAP.ALM.ANVIL.s.sol --broadcast --rpc-url http://127.0.0.1:8545

set_feed:
	clear && forge script scripts/SET.PRICE.FEED.s.sol --broadcast --rpc-url http://127.0.0.1:8545

mint_blocks:
	clear && anvil --block-time 1

# Deploy unichain

run_unichain_copy:
	clear && ./scripts/infisical_run.sh 'anvil --fork-block-number 27185697 --fork-url "$$UNICHAIN_RPC_URL" --no-storage-caching'

deploy:
	clear && python3 scripts/deploy.py

verify:
	clear && python3 scripts/unichain/verify.py --id 0

verify_one:
	clear && ./scripts/infisical_run.sh './scripts/unichain/verify.sh'