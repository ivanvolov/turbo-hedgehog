#!/usr/bin/env python3
import subprocess
import sys
import shlex
import questionary
import json
import os
import re
from typing import Any, Dict, List, Optional, Tuple, Union

# === Infisical configuration ===
INFISICAL_ENABLED = True
INFISICAL_ENV = "dev"
INFISICAL_PATH = "/IVa-laptop-forge"


def with_infisical(cmd: str) -> str:
    """Wrap a command so it runs with Infisical-provided env vars."""
    if not INFISICAL_ENABLED:
        return cmd
    return (
        f"infisical run --env={shlex.quote(INFISICAL_ENV)} "
        f"--path={shlex.quote(INFISICAL_PATH)} -- bash -c {shlex.quote(cmd)}"
    )


def clean_spaces(s: str) -> str:
    """Collapse repeated whitespace to a single space."""
    return re.sub(r"\s+", " ", s).strip()


def strip_broadcast(cmd: str) -> str:
    """
    Remove '--broadcast' flags safely from a command string (all occurrences).
    Then collapse extra spaces.
    """
    # Remove occurrences with surrounding whitespace handled
    without = re.sub(r"(?<!\S)--broadcast(?!\S)", "", cmd)
    return clean_spaces(without)


def save_session(path: List[str], SESSION_FILE: str) -> None:
    with open(SESSION_FILE, "w") as f:
        json.dump({"path": path}, f)


def load_session(SESSION_FILE: str) -> Optional[List[str]]:
    if not os.path.exists(SESSION_FILE):
        return None
    try:
        with open(SESSION_FILE) as f:
            data = json.load(f)
        return data.get("path")
    except Exception:
        return None


def is_leaf(node: Any) -> bool:
    """Leaf = command string OR dict with a 'cmd' field."""
    return isinstance(node, str) or (isinstance(node, dict) and "cmd" in node)


def traverse(
    root: Dict[str, Any], cached_path: Optional[List[str]] = None
) -> Tuple[Any, List[str]]:
    """
    Walk the nested dict until a leaf is reached.
    Reuse cached_path entries when they match; otherwise prompt.
    Returns (leaf_node, chosen_path_labels).
    """
    node: Any = root
    path: List[str] = []
    cached = list(cached_path) if cached_path else []

    while True:
        if is_leaf(node):
            return node, path

        if not isinstance(node, dict) or not node:
            print("Invalid command tree: encountered non-dict/non-leaf node.")
            sys.exit(1)

        keys = list(node.keys())

        if cached and cached[0] in node:
            choice = cached.pop(0)
        else:
            choice = questionary.select("Choose:", choices=keys).ask()
            if not choice:
                sys.exit(0)

        path.append(choice)
        node = node[choice]


def run_step(label: str, cmd: str) -> None:
    """Clear screen and run one command wrapped in Infisical."""
    wrapped = with_infisical(cmd)
    print(f"\n=== {label.upper()} ===\n{wrapped}\n")
    subprocess.run(["clear"])
    subprocess.run(wrapped, shell=True, check=True)


def execute_leaf(leaf: Union[str, Dict[str, Any]], path: List[str]) -> None:
    """
    Execute a leaf:
      - If string: run directly.
      - If object with 'cmd':
          * If dry_run_first: run 'cmd' without --broadcast as dry-run; on success ask to continue; then run full 'cmd'.
          * Else: run 'cmd' directly.
    """
    if isinstance(leaf, str):
        run_step(path[-1] if path else "command", leaf)
        return

    cmd = leaf["cmd"]
    dry_run_first = bool(leaf.get("dry_run_first"))

    if dry_run_first:
        dry_cmd = strip_broadcast(cmd)
        try:
            run_step("dry-run", dry_cmd)
        except subprocess.CalledProcessError as e:
            print(f"Dry-run failed with exit code {e.returncode}. Aborting.")
            sys.exit(e.returncode)

        sure = questionary.confirm(
            f"Dry-run succeeded.\nProceed to BROADCAST for: '{path[-1] if path else 'command'}' on {INFISICAL_ENV}?",
            default=False,
        ).ask()
        if not sure:
            print("Execution aborted by user.")
            sys.exit(0)
        
        # Require password to proceed
        password = questionary.password("Enter password to proceed:").ask()
        if password != "13489":
            print("Invalid password. Execution aborted.")
            sys.exit(0)

    # Run final/broadcast command
    run_step("broadcast" if dry_run_first else (path[-1] if path else "command"), cmd)


def run_nested(COMMANDS: Dict[str, Any], SESSION_FILE: str):
    # Offer retry using last path
    last_path = load_session(SESSION_FILE)
    retry_label = f"Retry last: {' / '.join(last_path)}" if last_path else None

    # Top-level: either retry or start traversing
    top_choices = ["Start new selection"]
    if retry_label:
        top_choices.insert(0, retry_label)

    top = questionary.select("What do you want to do?", choices=top_choices).ask()
    if not top:
        sys.exit(0)

    use_cached = retry_label and top == retry_label
    leaf, chosen_path = traverse(
        COMMANDS, cached_path=last_path if use_cached else None
    )

    # Save for next time
    save_session(chosen_path, SESSION_FILE)

    print("\n----------------------------------")
    print("Chosen path:")
    for i, p in enumerate(chosen_path, 1):
        print(f"{i:>2}. {p}")
    print("----------------------------------\n")

    # Execute the leaf
    execute_leaf(leaf, chosen_path)
