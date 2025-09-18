# Batches of tests

ta:
	clear && ./cmd/infisical_run.sh 'forge test -v --no-match-contract "SimulationTest"'

tam:
	clear && ./cmd/infisical_run.sh 'forge test -v --no-match-contract "Simulation|UNI_ALMTest|BASE_ALMTest|Oracle|LendingAdaptersTest"'

tau:
	clear && ./cmd/infisical_run.sh 'forge test -v --match-contract "UNI_ALMTest|BASE_ALMTest"'

# Strategies tests Mainnet

te:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_ALMTest --match-test "test_"'
tel:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_ALMTest --match-test "test_"'

ter:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_R_ALMTest --match-test "test_"'
terl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_R_ALMTest --match-test "test_"'

ter2:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_R2_ALMTest --match-test "test_"'
ter2l:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_R2_ALMTest --match-test "test_"'

tu:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract UNICORD_ALMTest --match-test "test_"'
tul:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract UNICORD_ALMTest --match-test "test_"'

tur:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract UNICORD_R_ALMTest --match-test "test_"'
turl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract UNICORD_R_ALMTest --match-test "test_"'

tb:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract BTC_ALMTest --match-test "test_"'
tbl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract BTC_ALMTest --match-test "test_"'

td:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract DeltaNeutral_ALMTest --match-test "test_"'
tdl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract DeltaNeutral_ALMTest --match-test "test_"'

tt:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract TURBO_ALMTest --match-test "test_"'
ttl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract TURBO_ALMTest --match-test "test_"'


# Strategies tests Unichain

teuu:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_UNICORD_UNI_ALMTest --match-test "test_"'
teuul:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_UNICORD_UNI_ALMTest --match-test "test_"'

teu:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_UNI_ALMTest --match-test "test_"'
teul:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_UNI_ALMTest --match-test "test_"'

pdeu:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract PRE_DEPOSIT_UNI_ALMTest --match-test "test_"'
pdeul:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract PRE_DEPOSIT_UNI_ALMTest --match-test "test_"'

teru:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_R_UNI_ALMTest --match-test "test_"'
terul:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_R_UNI_ALMTest --match-test "test_"'

ter2u:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_R2_UNI_ALMTest --match-test "test_"'
ter2ul:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_R2_UNI_ALMTest --match-test "test_"'

tuu:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract UNICORD_UNI_ALMTest --match-test "test_"'
tuul:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract UNICORD_UNI_ALMTest --match-test "test_"'

turu:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract UNICORD_R_UNI_ALMTest --match-test "test_"'
turul:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract UNICORD_R_UNI_ALMTest --match-test "test_"'

tdu:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract DeltaNeutral_UNI_ALMTest --match-test "test_"'
tdul:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract DeltaNeutral_UNI_ALMTest --match-test "test_"'

# Strategies tests Base

tbb:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract BTC_BASE_ALMTest --match-test "test_"'
tbbl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract BTC_BASE_ALMTest --match-test "test_"'

tdb:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract DeltaNeutral_R_BASE_ALMTest --match-test "test_"'
tdbl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract DeltaNeutral_R_BASE_ALMTest --match-test "test_"'

# Adapters tests

tg:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract General_ALMTest --match-test "test_"'
tgl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract General_ALMTest --match-test "test_"'

tla:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract LendingAdaptersTest --match-test "test_"'
tlal:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract LendingAdaptersTest --match-test "test_"'

tra:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract RewardsAdaptersTest --match-test "test_"'
tral:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract RewardsAdaptersTest --match-test "test_"'

tsa:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract SwapAdapterTest --match-test "test_"'
tsal:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract SwapAdapterTest --match-test "test_"'

to:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract OracleFuzzing --match-test "test_Fuzz" --fuzz-runs 5000
tol:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract OracleFuzzing --match-test "test_Fuzz" --fuzz-runs 5000

tom:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract OracleMathTest --match-test "test_"'
toml:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract OracleMathTest --match-test "test_"'

# Simulations

tes:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_simulation --ffi
tesl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_simulation --ffi

ters:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_rebalance_simulation --ffi
tersl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_rebalance_simulation --ffi

tess:
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_swaps_simulation --ffi
tessl:
	clear && ./cmd/infisical_run.sh 'forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_swaps_simulation --ffi

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
	clear && ./cmd/infisical_run.sh 'forge test -vv --match-contract "ETH_ALMTest\b" --match-test "test_lifecycle"
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

deploy:
	clear && python3 cmd/deploy.py

verify:
	clear && python3 cmd/verify.py --id 0

verify_one:
	clear && ./cmd/infisical_run.sh './scripts/unichain/verify.sh'