const { decodeHexString, saveToCSV } = require("./common");

const packedHexString = process.argv[2];
const args = decodeHexString(packedHexString, [
    "uint256",
    "bool",
    "bool",
    "uint256",
    "int256",
    "int256",
    "int256",
    "int256",
]);

saveToCSV("swaps", `${args.join(",")}\n`);
