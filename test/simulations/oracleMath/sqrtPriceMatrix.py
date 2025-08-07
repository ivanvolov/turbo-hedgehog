import numpy as np
import matplotlib.pyplot as plt
import math

# === tweak these three numbers to explore other regions ===
MIN_PRICE = 1
MAX_PRICE = 10e6*1e18
STEP      = MAX_PRICE/1e4
# ==========================================================

q96 = 2**96

# Generate 1-D grid of prices
prices = np.arange(MIN_PRICE, MAX_PRICE + STEP, STEP, dtype=np.float64)
size   = len(prices)

# Prepare a 2-D array for the resulting sqrtPriceX96 values
sqrt_px96 = np.empty((size, size), dtype=np.float64)  # Changed to float64

# Double loop over base (rows) and quote (cols)
for i, b in enumerate(prices):
    for j, q in enumerate(prices):
        try:
            # Use float arithmetic to avoid overflow
            # result = math.sqrt(1e18 * q * 1e18 / b) * q96 / 1e18
            result = b*q
            sqrt_px96[i, j] = result
        except (OverflowError, ValueError):
            sqrt_px96[i, j] = np.nan

# --- visualise -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(6, 5))
im      = ax.imshow(sqrt_px96, origin="lower", 
                    extent=[MIN_PRICE, MAX_PRICE, MIN_PRICE, MAX_PRICE],
                    interpolation="nearest")

ax.set_title("sqrtPriceX96 heat-map")
ax.set_xlabel("quotePrice")
ax.set_ylabel("basePrice")
fig.colorbar(im, ax=ax, label="sqrtPriceX96")

plt.tight_layout()
plt.show()
