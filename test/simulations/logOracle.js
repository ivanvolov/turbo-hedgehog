const { decodeHexString, saveToCSV } = require("./common");

const packedHexString = process.argv[2];
const args = decodeHexString(packedHexString, [
    "uint256",
    "uint256",
    "int256",
    "bool",
    "uint256",
    "uint160",
    "uint256",
]);

saveToCSV("oracles", `${args.join(",")}\n`);
