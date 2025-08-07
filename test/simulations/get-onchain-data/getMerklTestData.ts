const { MerklApi } = require("@merkl/api");

const merkl = MerklApi("https://api.merkl.xyz").v4;

const main = async () => {
  const rewards = await merkl
    .users({
      address: "0xB4E906060EABc5F30299e8098B61e41496a7233c",
    })
    .rewards.get({ query: { chainId: 1 } } as any);

  for (const reward of rewards.data[0].rewards) {
    console.log(reward);
  }
};

main();
