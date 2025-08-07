const { ethers } = require("ethers");
const fs = require("fs");

// --- CONFIG ---
const RPC_URL = "http://127.0.0.1:8545"; // Anvil RPC
const CONTRACT_ADDRESS = "0x82B769500E34362a76DF81150e12C746093D954F";
const ARTIFACT_PATH = "out/TestOracle.sol/TestOracle.json";

const STABLE_MIN = 1;
const STABLE_MAX = 10000;
const STABLE_STEP = 100;

const LONG_TAIL_MIN = 1;
const LONG_TAIL_MAX = 10e6;
const LONG_TAIL_STEP = 100000;

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

const results = [];

const artifact = JSON.parse(fs.readFileSync(ARTIFACT_PATH, "utf8"));
const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
const signer = provider.getSigner(0);
const oracle = new ethers.Contract(CONTRACT_ADDRESS, artifact.abi, signer);

async function main() {
    const startTime = Date.now();

    for (let priceStable = STABLE_MIN; priceStable <= STABLE_MAX; priceStable += STABLE_STEP) {
        for (let priceLongTail = LONG_TAIL_MIN; priceLongTail <= LONG_TAIL_MAX; priceLongTail += LONG_TAIL_STEP) {
            // ETH/USDT, ETH/USDC, WETH/USDT, WETH/USDC
            await call_all_combinations(tpP(priceStable, 18), tpP(priceLongTail, 18), 6 - 18);
            // call_all_combinations(tpP(priceStable, 8), tpP(priceLongTail, 8), 6 - 18);

            // // ETH/DAI, WETH/DAI
            // call_all_combinations(tpP(priceStable, 18), tpP(priceLongTail, 18), 18 - 18);
            // call_all_combinations(tpP(priceStable, 8), tpP(priceLongTail, 8), 18 - 18);

            // // CBBTC/USDT, CBBTC/USDC, WBTC/USDT, WBTC/USDC
            // call_all_combinations(tpP(priceStable, 18), tpP(priceLongTail, 18), 6 - 8);
            // call_all_combinations(tpP(priceStable, 8), tpP(priceLongTail, 8), 6 - 8);

            // // CBBTC/DAI, CBBTC/DAI, WBTC/DAI, WBTC/DAI
            // call_all_combinations(tpP(priceStable, 18), tpP(priceLongTail, 18), 18 - 8);
            // call_all_combinations(tpP(priceStable, 8), tpP(priceLongTail, 8), 18 - 8);
        }
    }

    // Save to JSON file
    fs.writeFileSync("test/simulations/out/oracle_results.json", JSON.stringify(results, null, 2));

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
    // await newOracleGetPrices(price0, price1, -totalDecDel, false);
    // await newOracleGetPrices(price0, price1, totalDecDel, true);
    // await newOracleGetPrices(price0, price1, -totalDecDel, true);

    // await newOracleGetPrices(price1, price0, totalDecDel, false);
    // await newOracleGetPrices(price1, price0, -totalDecDel, false);
    // await newOracleGetPrices(price1, price0, totalDecDel, true);
    // await newOracleGetPrices(price1, price0, -totalDecDel, true);
}

async function newOracleGetPrices(price0, price1, totalDecDel, isInverted) {
    const testCase = totalDecDel + "_" + isInverted;
    try {
        const [p, sqrt] = await oracle.getPrices(price0, price1, totalDecDel, isInverted);
        console;
        results.push({
            price0: price0.toString(),
            price1: price1.toString(),
            totalDecDel,
            isInverted,
            p: p.toString(),
            sqrt: sqrt.toString(),
            testCase: testCase,
        });
    } catch (err) {
        console.error(`Error for:`, err);
        process.exit(1);
    }
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
