#!/usr/bin/env python3
import subprocess
import sys
import shlex
import questionary
import json
import os

# === Infisical configuration ===
INFISICAL_ENABLED = True
INFISICAL_ENV = "prod"
INFISICAL_PATH = "/IVa-laptop-forge"

SESSION_FILE = "deploy.session"


def with_infisical(cmd: str) -> str:
    """Wrap a command so it runs with Infisical-provided env vars."""
    if not INFISICAL_ENABLED:
        return cmd
    return (
        f'infisical run --env={shlex.quote(INFISICAL_ENV)} '
        f'--path={shlex.quote(INFISICAL_PATH)} -- bash -c {shlex.quote(cmd)}'
    )


# === Forge commands for each action/target ===
FORGE_CMDS = {
    "oracles": {
        "pre-deploy": (
            'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol '
            '--broadcast --rpc-url http://127.0.0.1:8545'
        ),
        "dry-run": (
            'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol '
            '--rpc-url "$UNICHAIN_RPC_URL"'
        ),
        "deploy": (
            'forge script scripts/unichain/Deploy.Oracles.UNI.s.sol '
            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
        ),
    },
    "body": {
        "pre-deploy": (
            'forge script scripts/unichain/Deploy.ALM.UNI.s.sol '
            '--broadcast --rpc-url http://127.0.0.1:8545'
        ),
        "dry-run": (
            'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool)" false '
            '--rpc-url "$UNICHAIN_RPC_URL"'
        ),
        "deploy": (
            'forge script scripts/unichain/Deploy.ALM.UNI.s.sol --sig "run(bool)" false '
            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
        ),
    },
    "deposit": {
        "pre-deploy": (
            'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 0 '
            '--broadcast --rpc-url http://127.0.0.1:8545'
        ),
        "dry-run": (
            'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 0 '
            '--rpc-url "$UNICHAIN_RPC_URL"'
        ),
        "deploy": (
            'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 0 '
            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
        ),
    },
    "rebalance": {
        "pre-deploy": (
            'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 1 '
            '--broadcast --rpc-url http://127.0.0.1:8545'
        ),
        "dry-run": (
            'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 1 '
            '--rpc-url "$UNICHAIN_RPC_URL"'
        ),
        "deploy": (
            'forge script scripts/unichain/FD_R.ALM.UNI.s.sol --sig "run(uint256)" 1 '
            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
        ),
    },
}


def save_session(action: str, target: str) -> None:
    """Save the last chosen action/target to a session file."""
    data = {"action": action, "target": target}
    with open(SESSION_FILE, "w") as f:
        json.dump(data, f)


def load_session():
    """Load the last chosen action/target if the session file exists."""
    if not os.path.exists(SESSION_FILE):
        return None
    try:
        with open(SESSION_FILE) as f:
            return json.load(f)
    except Exception:
        return None


def run_step(label: str, cmd: str) -> None:
    """Clear screen and run one command wrapped in Infisical."""
    wrapped = with_infisical(cmd)
    print(f"\n=== {label.upper()} ===\n{wrapped}\n")
    subprocess.run(["clear"])
    subprocess.run(wrapped, shell=True, check=True)


def main():
    # --- Load last session (if any) ---
    last = load_session()
    retry_choice = None
    if last:
        # Offer a retry option on top
        retry_choice = f"Retry last action: {last['action']} on {last['target']}"

    # Step 1: Choose action or retry
    action_choices = []
    if retry_choice:
        action_choices.append(retry_choice)
    action_choices += ["pre-deploy", "dry-run", "deploy"]

    action = questionary.select(
        "Choose action:",
        choices=action_choices
    ).ask()
    if not action:
        sys.exit(0)

    # If the user chose to retry, reuse last session values
    if retry_choice and action == retry_choice:
        action = last["action"]
        target = last["target"]
        print(f"\nReusing previous choice: {action} on {target}\n")
    else:
        # Step 2: Choose target
        target = questionary.select(
            "Deploy target:",
            choices=list(FORGE_CMDS.keys())
        ).ask()
        if not target:
            sys.exit(0)

    # Save the new choice for next time
    save_session(action, target)

    print("\n----------------------------------")
    print(f"Action: {action}")
    print(f"Target: {target}")
    print("----------------------------------\n")

    # Step 3: Execute commands
    cmds = FORGE_CMDS[target]
    if action == "deploy":
        dry_cmd = cmds["dry-run"]
        deploy_cmd = cmds["deploy"]

        # Always run dry-run first
        try:
            run_step("dry-run", dry_cmd)
        except subprocess.CalledProcessError as e:
            print(f"Dry-run failed with exit code {e.returncode}. Deployment aborted.")
            sys.exit(e.returncode)

        # Confirmation before actual deployment
        sure = questionary.confirm(
            f"Dry-run succeeded.\nAre you sure you want to DEPLOY to '{target}' on {INFISICAL_ENV}?",
            default=False
        ).ask()
        if not sure:
            print("Deployment aborted by user.")
            sys.exit(0)

        # Run deploy
        run_step("deploy", deploy_cmd)

    else:
        cmd = cmds[action]
        run_step(action, cmd)


if __name__ == "__main__":
    main()
