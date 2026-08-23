#!/usr/bin/env python3
from typing import Any, Dict
from shared.interface import run_nested

SESSION_FILE = "build.session"

COMMANDS: Dict[str, Any] = {
    "build": {
        "build": ("forge clean && forge build"),
        "build with sizes": ("forge clean && forge build --sizes"),
        "clean": ("forge clean"),
    },
    "format": {
        "format": (
            'npx prettier --check "src/**/*.sol" "test/**/*.sol" "scripts/**/*s.sol" && black --check .'
        ),
        "format write": (
            'npx prettier --write "src/**/*.sol" "test/**/*.sol" "scripts/**/*s.sol" && black .'
        ),
        "lint": ("forge lint"),
    },
    "gas snapshot": {
        "match-contract": (
            'forge test -vv --match-contract "ETH_ALMTest\b" --match-test "test_lifecycle'
        ),
        "snapshot": (
            'forge snapshot --match-contract "ETH_ALMTest\b" --match-test "test_lifecycle"'
        ),
    },
    "capture onchain data": {
        "merkl data": ("npm run merkl"),
        "morpho data": ("npm run morpho"),
        "init pool events": ("npm run init_pool_events"),
    },
}


def main():
    run_nested(COMMANDS, SESSION_FILE)


if __name__ == "__main__":
    main()
