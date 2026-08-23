#!/usr/bin/env python3
from typing import Any, Dict
from shared.interface import run_nested

SESSION_FILE = "simulate.session"

COMMANDS: Dict[str, Any] = {
    "simulate ETH_ALM": {
        "basic": {
            "silent": (
                "forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_simulation --ffi"
            ),
            "logs": (
                "forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_simulation --ffi"
            ),
        },
        "rebalance": {
            "silent": (
                "forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_rebalance_simulation --ffi"
            ),
            "logs": (
                "forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_rebalance_simulation --ffi"
            ),
        },
        "swaps": {
            "silent": (
                "forge test -vv --match-contract ETH_ALMSimulationTest --match-test test_swaps_simulation --ffi"
            ),
            "logs": (
                "forge test -vvvv --match-contract ETH_ALMSimulationTest --match-test test_swaps_simulation --ffi"
            ),
        },
    },
    "simulate oracles": {
        "deploy": (
            "forge script scripts/DeployOracleSimulation.s.sol --rpc-url http://127.0.0.1:8545 --broadcast"
        ),
        "get_data": (
            "node --max-old-space-size=16384 --expose-gc test/simulations/oracleMath/anvilSim.s.js"
        ),
        "viz_data": ("python3 test/simulations/analytics/oracleFuzzing.py"),
    },
}


def main():
    run_nested(COMMANDS, SESSION_FILE)


if __name__ == "__main__":
    main()
