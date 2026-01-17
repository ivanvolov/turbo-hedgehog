#!/usr/bin/env python3
from typing import Any, Dict
from shared.interface import run_nested

SESSION_FILE = "deploy.session"

# ============================================================================
# Define ANY nested structure. Leaves (strings) are commands to execute.
# Keys are the menu labels shown to the user.
# ============================================================================
COMMANDS: Dict[str, Any] = {
    "anvil": {
        "deploy": {
            "oracles": {
                "mock feeds": (
                    'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(uint256)" 0 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "chronicle feeds": (
                    'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(uint256)" 1 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "api3 feeds": (
                    'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(uint256)" 2 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
            },
            "body": {
                "general": (
                    'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool,bool)" true false '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "pre-deposit": (
                    'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool,bool)" true true '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
            },
        },
        "operate": {
            "deposit": {
                "mainnet-size (Small) deposit": (
                    'forge script scripts/unichain/Deposit.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "test-size (Large) deposit": (
                    'forge script scripts/unichain/Deposit.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
            },
            "rebalance": {
                "general": (
                    'forge script scripts/unichain/Rebalance.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "pre-deposit": (
                    'forge script scripts/unichain/Rebalance.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
            },
            "swap": {
                "⬇️ mainnet-size (Small) swap": (
                    'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "⬇️ test-size (Large) swap": (
                    'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "⬆️ mainnet-size (Small) swap": (
                    'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 2 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "⬆️ test-size (Large) swap": (
                    'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 3 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
            },
        },
        "advanced": {
            "run_anvil_copy: mining": (
                'anvil --fork-block-number 37917524 --fork-url "$UNICHAIN_RPC_URL" --no-storage-caching --block-time 0.5'
            ),
            "run_anvil_copy: no-mining": (
                'anvil --fork-block-number 37917524 --fork-url "$UNICHAIN_RPC_URL" --no-storage-caching'
            ),
            "set_feed": (
                "forge script scripts/unichain/SET.FEED.UNI.s.sol "
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
            "move from pre-deposit to general": (
                "forge script scripts/unichain/Move.ALM.UNI.s.sol "
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
            "arbitrage": {
                "deploy": (
                    'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 5 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "ensure exclusive": (
                    'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 1 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "ensure non-exclusive": (
                    'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 2 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "calculate price ratio": (
                    'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 3 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
                "execute arbitrage": (
                    'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 4 '
                    "--broadcast --rpc-url http://127.0.0.1:8545"
                ),
            },
        },
    },
    "unichain": {
        "deploy": {
            "oracles": {
                "mock feeds": {
                    "dry-run": (
                        'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(uint256)" 0 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "broadcast": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(uint256)" 0 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
                "chronicle feeds": {
                    "dry-run": (
                        'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(uint256)" 1 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "broadcast": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(uint256)" 1 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
                "api3 feeds": {
                    "dry-run": (
                        'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(uint256)" 2 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "broadcast": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(uint256)" 2 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
            },
            "body": {
                "general": {
                    "dry-run": (
                        'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool,bool)" false false '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "broadcast": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool,bool)" false false '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
                "pre-deposit": {
                    "dry-run": (
                        'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool,bool)" false true '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "broadcast": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool,bool)" false true '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
            },
        },
        "operate": {
            "deposit": {
                "dry-run": {
                    "mainnet-size (Small) deposit": (
                        'forge script scripts/unichain/Deposit.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "test-size (Large) deposit": (
                        'forge script scripts/unichain/Deposit.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                },
                "broadcast": {
                    "mainnet-size (Small) deposit": {
                        "cmd": (
                            'forge script scripts/unichain/Deposit.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                    "test-size (Large) deposit": {
                        "cmd": (
                            'forge script scripts/unichain/Deposit.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
            },
            "rebalance": {
                "general": {
                    "dry-run": (
                        'forge script scripts/unichain/Rebalance.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "broadcast": {
                        "cmd": (
                            'forge script scripts/unichain/Rebalance.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
                "pre-deposit": {
                    "dry-run": (
                        'forge script scripts/unichain/Rebalance.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "broadcast": {
                        "cmd": (
                            'forge script scripts/unichain/Rebalance.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
            },
            "swap": {
                "dry-run": {
                    "⬇️ mainnet-size (Small) swap": (
                        'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "⬇️ test-size (Large) swap": (
                        'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "⬆️ mainnet-size (Small) swap": (
                        'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 2 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "⬆️ test-size (Large) swap": (
                        'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 3 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                },
                "broadcast": {
                    "⬇️ mainnet-size (Small) swap": {
                        "cmd": (
                            'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                    "⬇️ test-size (Large) swap": {
                        "cmd": (
                            'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                    "⬆️ mainnet-size (Small) swap": {
                        "cmd": (
                            'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 2 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                    "⬆️ test-size (Large) swap": {
                        "cmd": (
                            'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 3 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
            },
        },
        "advanced": {
            "set_feed": {
                "dry-run": (
                    "forge script scripts/unichain/SET.FEED.UNI.s.sol "
                    '--rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "broadcast": {
                    "cmd": (
                        "forge script scripts/unichain/SET.FEED.UNI.s.sol "
                        '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "dry_run_first": True,
                },
            },
            "move from pre-deposit to general": {
                "dry-run": (
                    "forge script scripts/unichain/Move.ALM.UNI.s.sol "
                    '--rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "broadcast": {
                    "cmd": (
                        "forge script scripts/unichain/Move.ALM.UNI.s.sol "
                        '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "dry_run_first": True,
                },
            },
            "arbitrage": {
                "dry-run": {
                    "deploy": (
                        'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 0 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "ensure exclusive": (
                        'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 1 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "ensure non-exclusive": (
                        'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 2 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "calculate price ratio": (
                        'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 3 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "execute arbitrage": (
                        'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 4 '
                        '--rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                },
                "broadcast": {
                    "deploy": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 0 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                    "ensure exclusive": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 1 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                    "ensure non-exclusive": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 2 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                    "calculate price ratio": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 3 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                    "execute arbitrage": {
                        "cmd": (
                            'forge script scripts/unichain/Deploy.ARB.UNI.s.sol --sig "run(uint256)" 4 '
                            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                        ),
                        "dry_run_first": True,
                    },
                },
            },
        },
    },
}


def main():
    run_nested(COMMANDS, SESSION_FILE)


if __name__ == "__main__":
    main()
