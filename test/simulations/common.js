const { BigNumber } = require("ethers");
const fs = require("fs");

function hexToBuffer(hex) {
    return Buffer.from(hex.replace(/^0x/, ""), "hex");
}

function decodeInt24BE(buffer, offset) {
    const bytes = buffer.slice(offset, offset + 3);
    const intValue = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
    return intValue & 0x800000 ? intValue | 0xff000000 : intValue;
}

function decodeDepositData(buffer, types) {
    const data = [];
    let offset = 0;

    for (const type of types) {
        switch (type) {
            case "uint256":
                data.push(BigNumber.from(buffer.slice(offset, offset + 32)).toString());
                offset += 32;
                break;
            case "address":
                data.push("0x" + buffer.slice(offset, offset + 20).toString("hex"));
                offset += 20;
                break;
            case "uint128":
                data.push(BigNumber.from(buffer.slice(offset, offset + 16)).toString());
                offset += 16;
                break;
            case "uint160":
                data.push(BigNumber.from(buffer.slice(offset, offset + 20)).toString());
                offset += 20;
                break;
            case "int24":
                data.push(decodeInt24BE(buffer, offset));
                offset += 3;
                break;
            case "int256":
                data.push(decodeInt256(buffer, offset));
                offset += 32;
                break;
            case "bool":
                data.push(buffer.readUInt8(offset) === 1);
                offset += 1;
                break;
            default:
                throw new Error(`Unsupported type: ${type}`);
        }
    }

    return data;
}

function decodeInt256(buffer, offset) {
    let intValue = BigInt("0x" + buffer.slice(offset, offset + 32).toString("hex"));
    const isNegative = intValue >= 1n << 255n;
    if (isNegative) {
        intValue -= 1n << 256n;
    }
    return intValue.toString();
}

function decodeHexString(hexString, types) {
    const buffer = hexToBuffer(hexString);
    return decodeDepositData(buffer, types);
}

function saveToCSV(name, csvData) {
    const csvFilePath = `test/simulations/out/${name}.csv`;
    fs.appendFileSync(csvFilePath, csvData, "utf8");
    console.log(`${name} data written to ${csvFilePath}`);
}

function prepareCsvFile(name, headerRow) {
    const filePath = `test/simulations/out/${name}.csv`;
    if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
    }
    fs.writeFileSync(filePath, headerRow, "utf8");
    console.log(`${filePath} prepared.`);
}

const randomNumber = (randomCap) => Math.floor(Math.random() * randomCap) + 1;

module.exports = {
    randomNumber,
    saveToCSV,
    decodeHexString,
    prepareCsvFile,
};
