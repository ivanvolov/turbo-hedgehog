const { decodeHexString, saveToCSV } = require("./common");

const packedHexString = process.argv[2];
const args = decodeHexString(packedHexString, [
    "uint256",
    "uint256",
    "address",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
    "uint256",
]);

saveToCSV("withdraws", `${args.join(",")}\n`);
