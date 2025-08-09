const { ethers } = require("ethers");
const fs = require("fs");

// --- CONFIG ---
const RPC_URL = "http://127.0.0.1:8545"; // Anvil RPC
const CONTRACT_ADDRESS = "0x82B769500E34362a76DF81150e12C746093D954F";
const ARTIFACT_PATH = "out/TestOracle.sol/TestOracle.json";

// From 0.5$ to 1.5$ with 1 cent step.
const STABLE_MIN = 50;
const STABLE_MAX = 150;
const STABLE_STEP = 1;

// From 1$ to 1mln$ with 1000$ step.
const LONG_TAIL_MIN = 1;
const LONG_TAIL_MAX = 200000;
const LONG_TAIL_STEP = 1000;

function tpP(price, POW) {
    return ethers.BigNumber.from(price).mul(ethers.BigNumber.from(10).pow(POW));
}

// Function to convert results to CSV format
function resultsToCSV(results) {
    if (results.length === 0) return "";

    // Get headers from the first result
    const headers = Object.keys(results[0]);
    const csvHeader = headers.join(",");

    // Convert each result to CSV row
    const csvRows = results.map((result) => {
        return headers
            .map((header) => {
                const value = result[header];
                // Escape quotes and wrap in quotes if contains comma or newline
                const escapedValue = String(value).replace(/"/g, '""');
                return `"${escapedValue}"`;
            })
            .join(",");
    });

    return [csvHeader, ...csvRows].join("\n");
}

// Function to create a unique query key
function createQueryKey(price0, price1, totalDecDel, isInverted) {
    return `${price0.toString()}_${price1.toString()}_${totalDecDel}_${isInverted}`;
}

// Memory management function
function manageMemory(operationCount) {
    if (operationCount % 20000 === 0) {
        if (global.gc) {
            global.gc();
            console.log(`Garbage collection performed at operation ${operationCount}`);
        }
    }
}

const results = [];
const queryCache = new Map(); // Single map: key -> { params, result }

const artifact = JSON.parse(fs.readFileSync(ARTIFACT_PATH, "utf8"));
const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
const signer = provider.getSigner(0);
const oracle = new ethers.Contract(CONTRACT_ADDRESS, artifact.abi, signer);

async function main() {
    const startTime = Date.now();
    let operationCount = 0;

    // Phase 1: Generate all test cases and collect unique queries
    console.log("Phase 1: Generating test cases and collecting unique queries...");

    for (let priceStable = STABLE_MIN; priceStable <= STABLE_MAX; priceStable += STABLE_STEP) {
        for (let priceLongTail = LONG_TAIL_MIN; priceLongTail <= LONG_TAIL_MAX; priceLongTail += LONG_TAIL_STEP) {
            // ETH/USDT, ETH/USDC, WETH/USDT, WETH/USDC
            await call_all_combinations(tpP(priceStable, 18), tpP(priceLongTail, 18), 6 - 18);
            await call_all_combinations(tpP(priceStable, 8), tpP(priceLongTail, 8), 6 - 18);

            // ETH/DAI, WETH/DAI
            await call_all_combinations(tpP(priceStable, 18), tpP(priceLongTail, 18), 18 - 18);
            await call_all_combinations(tpP(priceStable, 8), tpP(priceLongTail, 8), 18 - 18);

            // CBBTC/USDT, CBBTC/USDC, WBTC/USDT, WBTC/USDC
            await call_all_combinations(tpP(priceStable, 18), tpP(priceLongTail, 18), 6 - 8);
            await call_all_combinations(tpP(priceStable, 8), tpP(priceLongTail, 8), 6 - 8);

            // CBBTC/DAI, CBBTC/DAI, WBTC/DAI, WBTC/DAI
            await call_all_combinations(tpP(priceStable, 18), tpP(priceLongTail, 18), 18 - 8);
            await call_all_combinations(tpP(priceStable, 8), tpP(priceLongTail, 8), 18 - 8);

            operationCount += 8;
            manageMemory(operationCount);
        }
    }

    console.log(`Generated ${results.length} test cases with ${queryCache.size} unique queries`);

    // Phase 2: Make RPC calls for unique queries
    console.log("Phase 2: Making RPC calls for unique queries...");

    const totalQueries = queryCache.size;
    let completedQueries = 0;

    const TO_REPORT_EVERY = 500;

    for (const [queryKey, cacheEntry] of queryCache) {
        try {
            const [p, sqrt] = await oracle.getPrices(
                cacheEntry.params.price0,
                cacheEntry.params.price1,
                cacheEntry.params.totalDecDel,
                cacheEntry.params.isInverted,
            );

            // Store result directly in the same cache entry
            cacheEntry.result = { p: p.toString(), sqrt: sqrt.toString() };

            completedQueries++;

            // Report progress
            if (completedQueries % TO_REPORT_EVERY === 0) {
                const percentComplete = ((completedQueries / totalQueries) * 100).toFixed(2);
                console.log(`Progress: ${completedQueries}/${totalQueries} (${percentComplete}%)`);
            }
        } catch (err) {
            console.error(`Error for query ${queryKey}:`, err);
            process.exit(1);
        }
    }

    console.log(`Completed ${completedQueries} RPC calls`);

    // Phase 3: Insert results back into the original array
    console.log("Phase 3: Inserting results back into original array...");

    for (const result of results) {
        const queryKey = createQueryKey(
            ethers.BigNumber.from(result.price0),
            ethers.BigNumber.from(result.price1),
            result.totalDecDel,
            result.isInverted,
        );

        const cacheEntry = queryCache.get(queryKey);
        if (cacheEntry && cacheEntry.result) {
            result.p = cacheEntry.result.p;
            result.sqrt = cacheEntry.result.sqrt;
        } else {
            console.error(`Missing result for query key: ${queryKey}`);
            process.exit(1);
        }
    }

    // Save to JSON file
    // fs.writeFileSync("test/simulations/out/oracle_results.json", JSON.stringify(results, null, 2));

    // Save to CSV file
    const csvContent = resultsToCSV(results);
    fs.writeFileSync("test/simulations/out/oracle_results.csv", csvContent);

    const endTime = Date.now();
    const executionTimeMs = endTime - startTime;
    const executionTimeSeconds = executionTimeMs / 1000;
    const executionTimeMinutes = executionTimeSeconds / 60;

    console.log(`Fetched ${results.length} entries, saved to oracle_results.json and oracle_results.csv`);
    console.log(
        `Execution time: ${executionTimeMs}ms (${executionTimeSeconds.toFixed(2)}s / ${executionTimeMinutes.toFixed(2)}min)`,
    );
}

async function call_all_combinations(price0, price1, totalDecDel) {
    await newOracleGetPrices(price0, price1, totalDecDel, false);
    await newOracleGetPrices(price0, price1, -totalDecDel, false);
    await newOracleGetPrices(price0, price1, totalDecDel, true);
    await newOracleGetPrices(price0, price1, -totalDecDel, true);

    await newOracleGetPrices(price1, price0, totalDecDel, false);
    await newOracleGetPrices(price1, price0, -totalDecDel, false);
    await newOracleGetPrices(price1, price0, totalDecDel, true);
    await newOracleGetPrices(price1, price0, -totalDecDel, true);
}

async function newOracleGetPrices(price0, price1, totalDecDel, isInverted) {
    const testCase = totalDecDel + "_" + isInverted;
    const queryKey = createQueryKey(price0, price1, totalDecDel, isInverted);

    // Store the query parameters in the cache (only if not already present)
    if (!queryCache.has(queryKey)) {
        queryCache.set(queryKey, {
            params: {
                price0,
                price1,
                totalDecDel,
                isInverted,
            },
            result: null, // Will be populated in Phase 2
        });
    }

    // Add to results array with placeholder values
    results.push({
        price0: price0.toString(),
        price1: price1.toString(),
        totalDecDel,
        isInverted,
        p: "PLACEHOLDER", // Will be replaced in Phase 3
        sqrt: "PLACEHOLDER", // Will be replaced in Phase 3
        testCase: testCase,
    });
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
