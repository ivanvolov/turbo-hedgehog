#!/usr/bin/env python3
import argparse, json, shlex, subprocess
from pathlib import Path

DATA_FILE = Path("deployments/alm.unichain.json")
INFISICAL_ENV = "prod"
INFISICAL_PATH = "/IVa-laptop-forge"

def with_infisical(cmd: str) -> str:
    return (
        f'infisical run --env={shlex.quote(INFISICAL_ENV)} '
        f'--path={shlex.quote(INFISICAL_PATH)} -- bash -c {shlex.quote(cmd)}'
    )

def run(cmd: str):
    print("\n$ " + cmd)
    subprocess.run(with_infisical(cmd), shell=True, check=True)

def block_scout(addr: str, spec: str):
    run(
        f"forge verify-contract {addr} {spec} "
        "--chain-id 130 --verifier blockscout "
        "--verifier-url https://unichain.blockscout.com/api --watch"
    )

def etherscan(addr: str, spec: str):
    run(
        f"forge verify-contract {addr} {spec} "
        "--chain unichain --verifier etherscan "
        '--etherscan-api-key "$ETHERSCAN_API_KEY" --watch'
    )

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--id", type=int, required=True)
    args = parser.parse_args()

    data = json.loads(DATA_FILE.read_text())
    entry = data["alms"][args.id]

    for key, addr in entry["addresses"].items():
        spec = entry["paths"][key]
        print(f"\n=== {key}: {addr} ===")
        block_scout(addr, spec)
        etherscan(addr, spec)

if __name__ == "__main__":
    main()
