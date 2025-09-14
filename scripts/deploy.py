#!/usr/bin/env python3
import subprocess
import sys
import shlex
import questionary

# === Infisical configuration ===
INFISICAL_ENABLED = True
INFISICAL_ENV = "prod"
INFISICAL_PATH = "/IVa-laptop-forge"


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
            "forge script scripts/unichain/Deploy.Oracles.UNI.s.sol "
            "--broadcast --rpc-url http://127.0.0.1:8545"
        ),
        "dry-run": (
            "forge script scripts/unichain/Deploy.Oracles.UNI.s.sol "
            '--rpc-url "$UNICHAIN_RPC_URL"'
        ),
        "deploy": (
            "forge script scripts/unichain/Deploy.Oracles.UNI.s.sol "
            '--broadcast --rpc-url "$UNICHAIN_RPC_URL"'
        ),
    },
    "body": {
        # Replace with real commands when ready
        "pre-deploy": "echo 'body pre-deploy not implemented'",
        "dry-run": "echo 'body dry-run not implemented'",
        "deploy": "echo 'body deploy not implemented'",
    },
}


def run_step(label: str, cmd: str) -> None:
    """Clear screen and run one command wrapped in Infisical."""
    wrapped = with_infisical(cmd)
    print(f"\n=== {label.upper()} ===\n{wrapped}\n")
    subprocess.run(["clear"])
    subprocess.run(wrapped, shell=True, check=True)


def main():
    # Step 1: Choose action
    action = questionary.select(
        "Choose action:",
        choices=["pre-deploy", "dry-run", "deploy"]
    ).ask()
    if not action:
        sys.exit(0)

    # Step 2: Choose target
    target = questionary.select(
        "Deploy target:",
        choices=list(FORGE_CMDS.keys())
    ).ask()
    if not target:
        sys.exit(0)

    print("\n----------------------------------")
    print(f"Action: {action}")
    print(f"Target: {target}")
    print("----------------------------------\n")

    # Step 3: Execute commands
    cmds = FORGE_CMDS.get(target, {})
    if action == "deploy":
        dry_cmd = cmds.get("dry-run")
        deploy_cmd = cmds.get("deploy")
        if not dry_cmd or not deploy_cmd:
            print("Missing dry-run or deploy command for this target.")
            sys.exit(1)

        # Always run dry-run first
        try:
            run_step("dry-run", dry_cmd)
        except subprocess.CalledProcessError as e:
            print(f"Dry-run failed with exit code {e.returncode}. Deployment aborted.")
            sys.exit(e.returncode)

        # If dry-run succeeded, continue with deploy
        run_step("deploy", deploy_cmd)

    else:
        cmd = cmds.get(action)
        if not cmd:
            print("Command not found for this action/target.")
            sys.exit(1)
        run_step(action, cmd)


if __name__ == "__main__":
    main()
