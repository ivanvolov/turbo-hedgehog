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
        "oracles": {
            "deploy mock feeds": (
                'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(bool)" true '
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
            "deploy api3 feeds": (
                'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(bool)" true '
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
        },
        "body": (
            'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool)" true '
            "--broadcast --rpc-url http://127.0.0.1:8545"
        ),
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
        "rebalance": (
            'forge script scripts/unichain/Rebalance.ALM.UNI.s.sol --sig "run(uint256)" 0 '
            "--broadcast --rpc-url http://127.0.0.1:8545"
        ),
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
        "advanced": {
            "run_anvil_copy: mining": (
                'anvil --fork-block-number 30484160 --fork-url "$UNICHAIN_RPC_URL" --no-storage-caching --block-time 0.5'
            ),
            "run_anvil_copy: no-mining": (
                'anvil --fork-block-number 30484160 --fork-url "$UNICHAIN_RPC_URL" --no-storage-caching'
            ),
            "set_feed": (
                "forge script scripts/unichain/SET.FEED.UNI.s.sol "
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
        },
    },
    "unichain": {
        "oracles": {
            "dry-run: api3 feeds": (
                'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(bool)" false '
                '--rpc-url "$UNICHAIN_RPC_URL"'
            ),
            "deploy: api3 feeds": {
                "cmd": (
                    'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(bool)" false '
                    '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "dry_run_first": True,
            },
        },
        "body": {
            "dry-run": (
                'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool)" false '
                '--rpc-url "$UNICHAIN_RPC_URL"'
            ),
            "deploy": {
                "cmd": (
                    'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool)" false '
                    '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "dry_run_first": True,
            },
        },
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
            "deploy": {
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
            "dry-run": (
                'forge script scripts/unichain/Rebalance.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                '--rpc-url "$UNICHAIN_RPC_URL"'
            ),
            "deploy": {
                "cmd": (
                    'forge script scripts/unichain/Rebalance.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                    '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "dry_run_first": True,
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
            "deploy": {
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
        "advanced": {
            "set_feed": {
                "dry-run": (
                    "forge script scripts/unichain/SET.FEED.UNI.s.sol "
                    '--rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "deploy": {
                    "cmd": (
                        "forge script scripts/unichain/SET.FEED.UNI.s.sol "
                        '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                    ),
                    "dry_run_first": True,
                }
            }
        }
    }
}


def main():
    run_nested(COMMANDS, SESSION_FILE)


if __name__ == "__main__":
    main()
