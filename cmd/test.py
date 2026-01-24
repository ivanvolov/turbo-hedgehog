#!/usr/bin/env python3
from typing import Any, Dict
from shared.interface import run_nested

SESSION_FILE = "test.session"

COMMANDS: Dict[str, Any] = {
    "all": {
        "truly all": 'forge test -v --no-match-contract "SimulationTest"',
        "mainnet": 'forge test -v --no-match-contract "Simulation|UNI_ALMTest|BASE_ALMTest|Oracle|LendingAdaptersTest"',
        "unichain": 'forge test -v --match-contract "UNI_ALMTest|BASE_ALMTest"',
    },
    "strategy": {
        "ALM": {
            "ETH ALM": {
                "mainnet": {
                    "silent": (
                        'forge test -vv --match-contract ETH_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract ETH_ALMTest --match-test "test_"'
                    ),
                },
                "unichain": {
                    "silent": (
                        'forge test -vv --match-contract ETH_UNI_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract ETH_UNI_ALMTest --match-test "test_"'
                    ),
                },
            },
            "ETH Recursive ALM": {
                "mainnet": {
                    "silent": (
                        'forge test -vv --match-contract ETH_R_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract ETH_R_ALMTest --match-test "test_"'
                    ),
                },
                "unichain": {
                    "silent": (
                        'forge test -vv --match-contract ETH_R_UNI_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract ETH_R_UNI_ALMTest --match-test "test_"'
                    ),
                },
            },
            "ETH Recursive ALM version 2": {
                "mainnet": {
                    "silent": (
                        'forge test -vv --match-contract ETH_R2_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract ETH_R2_ALMTest --match-test "test_"'
                    ),
                },
                "unichain": {
                    "silent": (
                        'forge test -vv --match-contract ETH_R2_UNI_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract ETH_R2_UNI_ALMTest --match-test "test_"'
                    ),
                },
            },
            "BTC ALM": {
                "silent": (
                    'forge test -vv --match-contract BTC_ALMTest --match-test "test_"'
                ),
                "logs": (
                    'forge test -vvvv --match-contract BTC_ALMTest --match-test "test_"'
                ),
            },
            "TURBO ALM": {
                "mainnet": {
                    "silent": (
                        'forge test -vv --match-contract TURBO_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract TURBO_ALMTest --match-test "test_"'
                    ),
                },
                "unichain": {
                    "silent": (
                        'forge test -vv --match-contract TURBO_UNI_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract TURBO_UNI_ALMTest --match-test "test_"'
                    ),
                    "debug": (
                        'forge test --debug -vvvv --match-contract TURBO_UNI_ALMTest --match-test "test_deposit"'
                    ),
                },
            },
        },
        "UNICORD": {
            "STABLE": {
                "mainnet": {
                    "silent": (
                        'forge test -vv --match-contract UNICORD_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract UNICORD_ALMTest --match-test "test_"'
                    ),
                },
                "unichain": {
                    "silent": (
                        'forge test -vv --match-contract UNICORD_UNI_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract UNICORD_UNI_ALMTest --match-test "test_"'
                    ),
                },
            },
            "REVERTED": {
                "mainnet": {
                    "silent": (
                        'forge test -vv --match-contract UNICORD_R_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract UNICORD_R_ALMTest --match-test "test_"'
                    ),
                },
                "unichain": {
                    "silent": (
                        'forge test -vv --match-contract UNICORD_R_UNI_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract UNICORD_R_UNI_ALMTest --match-test "test_"'
                    ),
                },
            },
        },
        "DN": {
            "mainnet": {
                "silent": (
                    'forge test -vv --match-contract DeltaNeutral_ALMTest --match-test "test_"'
                ),
                "logs": (
                    'forge test -vvvv --match-contract DeltaNeutral_ALMTest --match-test "test_"'
                ),
            },
            "unichain": {
                "silent": (
                    'forge test -vv --match-contract DeltaNeutral_UNI_ALMTest --match-test "test_"'
                ),
                "logs": (
                    'forge test -vvvv --match-contract DeltaNeutral_UNI_ALMTest --match-test "test_"'
                ),
            },
            "base": {
                "BTC": {
                    "silent": (
                        'forge test -vv --match-contract BTC_BASE_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract BTC_BASE_ALMTest --match-test "test_"'
                    ),
                },
                "Reverted": {
                    "silent": (
                        'forge test -vv --match-contract DeltaNeutral_R_BASE_ALMTest --match-test "test_"'
                    ),
                    "logs": (
                        'forge test -vvvv --match-contract DeltaNeutral_R_BASE_ALMTest --match-test "test_"'
                    ),
                },
            },
        },
    },
    "adapters": {
        "general": {
            "silent": (
                'forge test -vv --match-contract General_ALMTest --match-test "test_"'
            ),
            "logs": (
                'forge test -vvvv --match-contract General_ALMTest --match-test "test_"'
            ),
        },
        "lending": {
            "silent": (
                'forge test -vv --match-contract LendingAdaptersTest --match-test "test_"'
            ),
            "logs": (
                'forge test -vvvv --match-contract LendingAdaptersTest --match-test "test_"'
            ),
        },
        "rewards": {
            "silent": (
                'forge test -vv --match-contract RewardsAdaptersTest --match-test "test_"'
            ),
            "logs": (
                'forge test -vvvv --match-contract RewardsAdaptersTest --match-test "test_"'
            ),
        },
        "swap": {
            "silent": (
                'forge test -vv --match-contract SwapAdapterTest --match-test "test_"'
            ),
            "logs": (
                'forge test -vvvv --match-contract SwapAdapterTest --match-test "test_"'
            ),
        },
        "oracle fuzzing": {
            "silent": (
                'forge test -vv --match-contract OracleFuzzing --match-test "test_Fuzz" --fuzz-runs 5000'
            ),
            "logs": (
                'forge test -vvvv --match-contract OracleFuzzing --match-test "test_Fuzz" --fuzz-runs 5000'
            ),
        },
        "oracle math": {
            "silent": (
                'forge test -vv --match-contract OracleMathTest --match-test "test_"'
            ),
            "logs": (
                'forge test -vvvv --match-contract OracleMathTest --match-test "test_"'
            ),
        },
    },
    "mixins": {
        "ETH ALM throw UNICORD swap": {
            "silent": (
                'forge test -vv --match-contract ETH_UNICORD_UNI_ALMTest --match-test "test_"'
            ),
            "logs": (
                'forge test -vvvv --match-contract ETH_UNICORD_UNI_ALMTest --match-test "test_"'
            ),
        },
        "ETH ALM pre deposit": {
            "silent": (
                'forge test -vv --match-contract PRE_DEPOSIT_UNI_ALMTest --match-test "test_"'
            ),
            "logs": (
                'forge test -vvvv --match-contract PRE_DEPOSIT_UNI_ALMTest --match-test "test_"'
            ),
        },
        "Arbitrage ALM UNISWAP": {
            "silent": (
                'forge test -vv --match-contract ARB_ETH_UNI_ALMTest --match-test "test_"'
            ),
            "logs": (
                'forge test -vvvv --match-contract ARB_ETH_UNI_ALMTest --match-test "test_"'
            ),
        },
        "Rebalance in production": {
            "silent": (
                'forge test -vv --match-contract REB_PROD_ALMTest --match-test "test_"'
            ),
            "logs": (
                'forge test -vvvv --match-contract REB_PROD_ALMTest --match-test "test_"'
            ),
        },
    },
}


def main():
    run_nested(COMMANDS, SESSION_FILE)


if __name__ == "__main__":
    main()
