const { prepareCsvFile } = require("./common");

const swapsHeaderRow = "amount, zFo, In, bN, delta0, delta1, delta0c, delta1c, preSqrtPrice, postSqrtPrice\n";
prepareCsvFile("swaps", swapsHeaderRow);

const statesHeaderRow = "bN, sqrtC, liq, sqrt, tL, tU, CL, CS, DL, DS, tvl, tvlControl, shareP, sharePc\n";
prepareCsvFile("states", statesHeaderRow);

const depositsHeaderRow = "amount, actor, bN, dWETH, dWETHc, dUSDCc, dSH, dSHc\n";
prepareCsvFile("deposits", depositsHeaderRow);

const withdrawsHeaderRow = "shares1, shares2, actor, bN, dWETH, dUSDC, dWETHc, dUSDCc\n";
prepareCsvFile("withdraws", withdrawsHeaderRow);

const rebalancesHeaderRow = "liquidity, priceT, aTT, bN\n";
prepareCsvFile("rebalances", rebalancesHeaderRow);
