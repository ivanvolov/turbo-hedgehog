#!/usr/bin/env python3
from typing import Any, Dict
from shared.interface import run_nested

SESSION_FILE = "deploy.session"

# ============================================================================
# Define ANY nested structure. Leaves (strings) are commands to execute.
# Keys are the menu labels shown to the user.
# ============================================================================
COMMANDS: Dict[str, Any] = {
    "oracles": {
        "anvil mock feeds": (
            'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(bool)" true '
            "--broadcast --rpc-url http://127.0.0.1:8545"
        ),
        "anvil api3 feeds": (
            'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(bool)" true '
            "--broadcast --rpc-url http://127.0.0.1:8545"
        ),
        "dry-run": (
            'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(bool)" false '
            '--rpc-url "$UNICHAIN_RPC_URL"'
        ),
        "deploy": {
            "cmd": (
                'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol --sig "run(bool)" false '
                '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
            ),
            "dry_run_first": True,
        },
    },
    "body": {
        "anvil": (
            'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool)" true '
            "--broadcast --rpc-url http://127.0.0.1:8545"
        ),
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
        "anvil": {
            "Mainnet-size deposit": (
                'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
            "Test-size deposit": (
                'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 3 '
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
        },
        "dry-run": (
            'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 0 '
            '--rpc-url "$UNICHAIN_RPC_URL"'
        ),
        "deploy": {
            "Mainnet-size deposit": {
                "cmd": (
                    'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                    '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "dry_run_first": True,
            },
            "Test-size deposit": {
                "cmd": (
                    'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 3 '
                    '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "dry_run_first": True,
            },
        },
    },
    "rebalance": {
        "anvil": (
            'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 1 '
            "--broadcast --rpc-url http://127.0.0.1:8545"
        ),
        "dry-run": (
            'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 1 '
            '--rpc-url "$UNICHAIN_RPC_URL"'
        ),
        "deploy": {
            "cmd": (
                'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
            ),
            "dry_run_first": True,
        },
    },
    "swap": {
        "anvil": {
            "Mainnet-size swap": (
                'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
            "Test-size swap": (
                'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
        },
        "dry-run": (
            'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 0 '
            '--rpc-url "$UNICHAIN_RPC_URL"'
        ),
        "deploy": {
            "Mainnet-size swap": {
                "cmd": (
                    'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 0 '
                    '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "dry_run_first": True,
            },
            "Test-size swap": {
                "cmd": (
                    'forge script scripts/unichain/SWAP.ALM.UNI.s.sol --sig "run(uint256)" 1 '
                    '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "dry_run_first": True,
            },
        },
    },
    "advanced": {
        "run_anvil_copy": {
            "cmd": (
                'anvil --fork-block-number 30484160 --fork-url "$UNICHAIN_RPC_URL" --no-storage-caching'
            )
        },
        "set_feed": {
            "anvil": (
                "forge script scripts/unichain/SET.FEED.UNI.s.sol "
                "--broadcast --rpc-url http://127.0.0.1:8545"
            ),
            "dry-run": (
                "forge script scripts/unichain/SET.FEED.UNI.s.sol "
                '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
            ),
            "deploy": {
                "cmd": (
                    "forge script scripts/unichain/SET.FEED.UNI.s.sol "
                    '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
                ),
                "dry_run_first": True,
            },
        },
    },
}


def main():
    run_nested(COMMANDS, SESSION_FILE)


if __name__ == "__main__":
    main()
