// const { utils } = require("ethers");
// const { randomNumber } = require("./common");

// const depositProbabilityPerBlock = 20; // Probability of deposit per block
// const maxDeposits = 20; // The maximum number of deposits. Set to max(uint256) to disable

// const withdrawProbabilityPerBlock = 7; // Probability of withdraw per block
// const maxWithdraws = 3; // The maximum number of withdraws. Set to max(uint256) to disable

// const numberOfSwaps = 100; // Number of blocks with swaps

// const maxDepositors = 3; // The maximum number of depositors
// const depositorReuseProbability = 50; // 50 % prob what the depositor will be reused rather then creating new one

// let depositsRemained = maxDeposits;
// let withdrawsRemained = maxWithdraws;

// for (let i = 0; i < numberOfSwaps; i++) {
//     // **  Always do swaps
//     {
//         randomAmount = random(10) * 1e18;
//         bool zeroForOne = (random(2) == 1);
//         bool _in = (random(2) == 1);

//         // Now will adjust amount if it's USDC goes In
//         if ((zeroForOne && _in) || (!zeroForOne && !_in)) {
//             console.log("> randomAmount before", randomAmount);
//             randomAmount = (randomAmount * expectedPoolPriceForConversion) / 1e12;
//         } else {
//             console.log("> randomAmount", randomAmount);
//         }

//         swap(randomAmount, zeroForOne, _in);
//     }

//     save_pool_state();

//     // ** Do random deposits
//     if (depositsRemained > 0) {
//         randomAmount = random(100);
//         if (randomAmount <= depositProbabilityPerBlock) {
//             randomAmount = random(10);
//             address actor = chooseDepositor();
//             deposit(randomAmount * 1e18, actor);
//             save_pool_state();
//             depositsRemained--;
//         }
//     }

//     // ** Do random withdraws
//     if (withdrawsRemained > 0) {
//         randomAmount = random(100);
//         if (randomAmount <= withdrawProbabilityPerBlock) {
//             address actor = getDepositorToReuse();
//             if (actor != address(0)) {
//                 randomAmount = random(100); // It is percent here

//                 withdraw(randomAmount, randomAmount, actor);
//                 save_pool_state();
//                 withdrawsRemained--;
//             }
//         }
//     }

//     // ** Roll block after each iteration
//     vm.roll(block.number + 1);
//     vm.warp(block.timestamp + 12);
// }
