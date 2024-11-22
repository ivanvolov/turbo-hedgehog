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
	clear && forge test -vv --match-test test_hook_deployment_exploit_revert
tl:
	clear && forge test -vvvv --match-test test_hook_deployment_exploit_revert

t2:
	clear && forge test -vv --match-test test_quick_test
t2l:
	clear && forge test -vvvv --match-test test_quick_test

spell:
	clear && cspell "**/*.*"