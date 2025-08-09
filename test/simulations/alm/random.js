const { utils } = require("ethers");
const { decodeHexString, randomNumber } = require("./common");

const packedHexString = process.argv[2];
const [randomCap] = decodeHexString(packedHexString, ["uint256"]);

const _randomNumber = randomNumber(randomCap);

// ** This is for testing only
// const csvFilePath = "test/snapshots/temp.txt";
// const csvData = `${randomNumber},${randomCap}\n`;
// fs.appendFileSync(csvFilePath, csvData, "utf8");
// console.log(randomNumber);

const resultBuffer = utils.defaultAbiCoder.encode(["uint256"], [_randomNumber]);
console.log(resultBuffer.toString("hex"));
