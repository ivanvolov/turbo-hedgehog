ta:
	clear && forge test -vv

ts:
	clear && forge test -vv --match-test test_simulation --ffi
tsl:
	clear && forge test -vvvv --match-test test_simulation --ffi

trs:
	clear && forge test -vv --match-test test_rebalance_simulation --ffi
trsl:
	clear && forge test -vvvv --match-test test_rebalance_simulation --ffi

t:
	clear && forge test -vv --match-test test_aave_lending_adapter_short
tl:
	clear && forge test -vvvv --match-test test_aave_lending_adapter_short

spell:
	clear && cspell "**/*.*"