const Web3 = require("web3");
const fs = require("fs");
const dotenv = require("dotenv");
dotenv.config();

const PoolManagerABI = require("./abi/PoolManagerABI.json");
const INFURA_MAINNET_URL = `https://mainnet.infura.io/v3/YOUR-PROJECT-ID/${process.env.INFURA_MAINNET_PROJECT_ID}`;
const web3 = new Web3(new Web3.providers.HttpProvider(INFURA_MAINNET_URL));
const POOL_MANAGER_ADDRESS = "0x000000000004444c5dc75cB358380D2e3dE08A90";

const contract = new web3.eth.Contract(PoolManagerABI, POOL_MANAGER_ADDRESS);
const START_BLOCK = 21688329;

async function getInitializeEvents() {
    const currentBlock = await web3.eth.getBlockNumber();
    console.log("Current block: ", currentBlock);

    const time_period = { fromBlock: START_BLOCK, toBlock: currentBlock };
    const eventsDeposit = await contract.getPastEvents("Initialize", time_period);

    console.log(eventsDeposit.length);
    const events = [];
    for (let i = 0; i < eventsDeposit.length; i++) {
        events.push({
            tx_hash: eventsDeposit[i].transactionHash,
            block_number: eventsDeposit[i].blockNumber,
            id: eventsDeposit[i].returnValues.id,
            currency0: eventsDeposit[i].returnValues.currency0,
            currency1: eventsDeposit[i].returnValues.currency1,
            fee: eventsDeposit[i].returnValues.fee,
            tickSpacing: eventsDeposit[i].returnValues.tickSpacing,
            hooks: eventsDeposit[i].returnValues.hooks,
        });
    }
    fs.writeFileSync("./test/simulations/out/pool_events.json", JSON.stringify(events, null, 2));
    console.log("Events saved to pool_events.json");
}

getInitializeEvents();
