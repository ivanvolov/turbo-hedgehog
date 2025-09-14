#!/bin/bash

# Check if command argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 \"<command>\""
    echo "Example: $0 \"anvil --fork-block-number 27111722 --fork-url \\\$UNICHAIN_RPC_URL\""
    exit 1
fi

# Clear terminal and run infisical with the provided command
clear && infisical run --env=prod --path=/IVa-laptop-forge -- bash -c "$1"