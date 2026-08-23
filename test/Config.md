# Test Configuration Parameters

This document provides a complete overview of the `init_hook` and `create_oracle` parameters across all test files.

## Complete Statistics Table

| Chain | isInvertedAssets | isNova | isInvertedPool | File Name |
|-------|-----------------|--------|----------------|-----------|
| **Strategies** |
| mainnet | false | false | true | test/strategies/eth/ETH.ALM.t.sol |
| mainnet | false | false | false | test/strategies/eth/ETH.R.ALM.t.sol |
| mainnet | false | false | false | test/strategies/eth/ETH.R2.ALM.t.sol |
| mainnet | **false** | **false** | **true** (config) | test/strategies/eth/TURBO.ALM.t.sol |
| mainnet | false | false | true | test/strategies/btc/BTC.ALM.t.sol |
| mainnet | true | false | true | test/strategies/dn/DN.ALM.t.sol |
| mainnet | false | true | true | test/strategies/unicord/UNICORD.ALM.t.sol |
| mainnet | true | true | false | test/strategies/unicord/UNICORD.R.ALM.t.sol |
| **Production** |
| unichain | false | false | false | test/production/eth/ETH.UNI.ALM.t.sol |
| unichain | false | false | false | test/production/eth/ETH.R.UNI.ALM.t.sol |
| unichain | false | false | false | test/production/eth/ETH.R2.UNI.ALM.t.sol |
| unichain | **false** | **false** | **true** (config) | test/production/eth/TURBO.UNI.ALM.t.sol |
| Base | false | false | true | test/production/btc/BTC.BASE.ALM.t.sol |
| unichain | true | false | false | test/production/dn/DN.UNI.ALM.t.sol |
| Base | true | false | true | test/production/dn/DN.R.BASE.ALM.t.sol |
| unichain | false | true | true | test/production/unicord/UNICORD.UNI.ALM.t.sol |
| unichain | false | true | false | test/production/unicord/UNICORD.R.UNI.ALM.t.sol |