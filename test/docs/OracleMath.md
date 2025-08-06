# Python

import math
q96 = 2**96
q32 = 2**32
uint256Max = 2\*\*256-1

### How to get price quote in terms of base out of sqrtPrice

p = (sqrt/q96)\*\*2
if target_pool B:Q => int(1e18/p)
if target_pool Q:B => int(1e18\*p)

# (0)

int(math.sqrt(1e18*q*1e18/b)\*q96/1e18)

# (1)

int((uint256Max/math.sqrt(b\*uint256Max/q))/q32)

# (2)

int(math.sqrt(uint256Max\*q/b)/q32)

# TODO:

- Fuzz all created oracles.
- Oracle tasks from notion to prod.
- Make simulations from existing fuzzing.
- Fix all tests
- Clean Code.
