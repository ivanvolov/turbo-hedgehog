const { decodeHexString, saveToCSV } = require("./common");

const packedHexString = process.argv[2];
const args = decodeHexString(packedHexString, ["uint128", "uint256", "uint256", "uint256"]);

saveToCSV("rebalances", `${args.join(",")}\n`);
