const { decodeHexString, saveToCSV } = require("./common");

const packedHexString = process.argv[2];
const args = decodeHexString(packedHexString, ["int24", "uint256"]);

saveToCSV("rebalances", `${args.join(",")}\n`);
