import axios from "axios";

interface MorphoDistribution {
  [key: string]: any;
}

async function getMorphoDistributions(
  address: string,
): Promise<MorphoDistribution[]> {
  const response = await axios.get(
    `https://rewards.morpho.org/v1/users/${address}/distributions`,
  );
  return response.data;
}

const address = "0xC977d218Fde6A39c7aCE71C8243545c276B48931";

async function main() {
  const distributions: any = await getMorphoDistributions(address);
  console.log(distributions.data);
}

main();
