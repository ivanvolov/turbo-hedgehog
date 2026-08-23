#!/usr/bin/env python3
from typing import Any, Dict
from shared.interface import run_nested

SESSION_FILE = "verify.session"

# ============================================================================
# Define ANY nested structure. Leaves (strings) are commands to execute.
# Keys are the menu labels shown to the user.
# ============================================================================
COMMANDS: Dict[str, Any] = {
    "all": {
        "id-1": ("python3 cmd/verify/all.py --id 0"),
        "id-2": ("python3 cmd/verify/all.py --id 1"),
        "id-3": ("python3 cmd/verify/all.py --id 2"),
    },
    "arbitrage": {
        "id-1": ("python3 cmd/verify/arbitrage.py --id 0"),
        "id-2": ("python3 cmd/verify/arbitrage.py --id 1"),
        "id-3": ("python3 cmd/verify/arbitrage.py --id 2"),
    },
    "one": ("./cmd/verify/one.sh"),
}


def main():
    run_nested(COMMANDS, SESSION_FILE)


if __name__ == "__main__":
    main()
