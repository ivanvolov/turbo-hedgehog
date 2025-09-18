#!/bin/bash

forge verify-contract \
  0xB97Ae60106E02939835466b473186A4832A32A32 \
  src/core/flashLoanAdapters/MorphoFlashLoanAdapter.sol:MorphoFlashLoanAdapter \
  --chain-id 130 \
  --verifier blockscout \
  --verifier-url https://unichain.blockscout.com/api \
  --watch

forge verify-contract \
  0xB97Ae60106E02939835466b473186A4832A32A32 \
  src/core/flashLoanAdapters/MorphoFlashLoanAdapter.sol:MorphoFlashLoanAdapter \
  --chain unichain \
  --verifier etherscan \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --watch