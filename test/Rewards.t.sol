// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// ** contracts
import {MorphoTestBase} from "@test/core/MorphoTestBase.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingAdapterEuler} from "@test/interfaces/ILendingAdapterEuler.sol";
import {IMerklDistributor, MerkleTree} from "@merkl-contracts/IMerklDistributor.sol";
import {
    IUniversalRewardsDistributor,
    PendingRoot
} from "@universal-rewards-distributor/IUniversalRewardsDistributor.sol";
import {ILendingAdapterMorpho} from "./interfaces/ILendingAdapterMorpho.sol";

contract RewardsAdaptersTest is MorphoTestBase {
    using SafeERC20 for IERC20;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    IMerklDistributor MRD = TestLib.merklRewardsDistributor;
    IUniversalRewardsDistributor URD = TestLib.universalRewardsDistributor;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(22119929);
    }

    address targetUser = 0xB4E906060EABc5F30299e8098B61e41496a7233c;
    IERC20 constant EUL = IERC20(0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b);
    IERC20 constant MORPHO = IERC20(0x58D97B57BB95320F9a05dC918Aef65434969c2B2);

    // claim some rewards and withdraw through adapter
    function test_lending_adapter_euler_rewards_and_claim() public {
        vm.rollFork(22469023);
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_euler_WETH_USDC();
        _fakeSetComponents(address(lendingAdapter), alice.addr); // ** Enable Alice to call the adapter

        uint256 amount = 183012673785523122481;

        assertEq(TestLib.rEUL.balanceOf(address(lendingAdapter)), 0, "before");

        // ** Claim rEUL
        {
            bytes32[] memory proof = new bytes32[](1);
            proof[0] = 0xc41888d0709f07a669eaa5faecc34122980bd31f12a174eb9bc6ab3a1b46811e;

            // ** Update root to allow our fake proof
            {
                vm.prank(0x435046800Fb9149eE65159721A92cB7d50a7534b); // root updater
                MRD.updateTree(
                    MerkleTree(_verifyProof(address(lendingAdapter), address(TestLib.rEUL), amount, proof), bytes32(0))
                );
                vm.warp(MRD.endOfDisputePeriod());
            }

            // ** Claim rewards
            vm.prank(deployer.addr);
            ILendingAdapterEuler(address(lendingAdapter)).claimMerklRewards(
                address(lendingAdapter),
                IERC20(address(TestLib.rEUL)),
                amount,
                proof
            );
        }

        assertEq(TestLib.rEUL.balanceOf(address(lendingAdapter)), amount, "after");
        assertEq(EUL.balanceOf(alice.addr), 0, "before");

        // ** Withdraw EUL
        {
            vm.warp(block.timestamp + 180 days);

            uint256[] memory ts_array = TestLib.rEUL.getLockedAmountsLockTimestamps(address(lendingAdapter));

            vm.prank(deployer.addr);
            ILendingAdapterEuler(address(lendingAdapter)).unlockRewardEUL(alice.addr, ts_array[0]);
        }

        assertEq(TestLib.rEUL.balanceOf(address(lendingAdapter)), 0, "after");
        assertEq(EUL.balanceOf(alice.addr), amount, "after");
    }

    // claim some rewards and withdraw through adapter
    function test_lending_adapter_morpho_claim() public {
        vm.rollFork(22476376 - 1);
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");
        create_lending_adapter_morpho();
        _fakeSetComponents(address(lendingAdapter), alice.addr); // ** Enable Alice to call the adapter

        uint256 amount = 30151918784160194072;
        assertEq(MORPHO.balanceOf(alice.addr), 0, "before");

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x302ac0237181fdc70530e69cdda68df1b7ce4853c1f30d8d289da066db747f8f;

        // ** Set fake root
        {
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(address(lendingAdapter), MORPHO, amount))));
            bytes32 proofRoot = MerkleProof.processProof(proof, leaf);
            vm.prank(0x640428D38189B11B844dAEBDBAAbbdfbd8aE0143);
            URD.submitRoot(proofRoot, bytes32(0));

            PendingRoot memory root = URD.pendingRoot();
            vm.warp(root.validAt);
            URD.acceptRoot();

            MerkleProof.verify(
                proof,
                URD.root(),
                keccak256(bytes.concat(keccak256(abi.encode(address(lendingAdapter), MORPHO, amount))))
            );
        }

        // ** Claim rewards
        vm.prank(deployer.addr);
        ILendingAdapterMorpho(address(lendingAdapter)).claimRewards(alice.addr, MORPHO, amount, proof);

        // It eq amount because it was not claimed before, but usually it is not equal
        assertEq(MORPHO.balanceOf(alice.addr), amount, "after");
    }

    // recreate last claim and withdraw 20$ and burn other 80%
    function test_rewards_euler_recreate_claims() public {
        vm.rollFork(22159144 - 1);

        // ** Claim rEUL
        {
            uint256 _before = TestLib.rEUL.balanceOf(targetUser);
            assertEq(_before, 0, "before");

            address[] memory users = new address[](1);
            users[0] = targetUser;
            address[] memory tokens = new address[](1);
            tokens[0] = address(TestLib.rEUL);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 170831077052791407402;

            bytes32[][] memory proofs = new bytes32[][](1);
            proofs[0] = new bytes32[](17);
            proofs[0][0] = 0x31c3f64d4cac4d8de18d68f582da5401204c0dfc5a8dc4b8bd029c74fb17d3e1;
            proofs[0][1] = 0xc1cd191e1daa3b67ded97b07ee25e7a371342d369dca3a15326645c99c675f72;
            proofs[0][2] = 0xbd2978be92998182cbeab4f885cc0d593d0bef4cdbc26e63a33cf18deec5b446;
            proofs[0][3] = 0xcc34981731bd21ee085b75930c199a5fdb3935aa4bed33dd884d98366d4eef29;
            proofs[0][4] = 0xcda3f7e37672d8779949333262b84679d55c9e5fccfb0aa7facc5efbb3916259;
            proofs[0][5] = 0xc655bca845893235ae7a9cce99640c64456ff3e8e2212d1940ca6e0b5a7fd891;
            proofs[0][6] = 0x910ca5feb69ee4beb9494d2dc805bf5139a6b048c0c044b64dcc2d3b66695cd5;
            proofs[0][7] = 0xde7c1a6a58023fc065e0726ebb7592d45e23ffe99ce982216fb64ebace01b30e;
            proofs[0][8] = 0xf613e9ef507a88ea3ca66c0de402fd303e6516dbd2c8a43baefc0bdd094501a2;
            proofs[0][9] = 0x0e630047f5c7a4effe1134d37b3a402c66ae56ca552edacb2e76157a385990d0;
            proofs[0][10] = 0xeb9881ddd33ca25947552b87ac851a575a88251c31b43153829be5b45f2c39dd;
            proofs[0][11] = 0xe49d7542993145c08e5bc58460789b895805913ca5e06576f60e3871b472a0bb;
            proofs[0][12] = 0x16d398c9ab85ae740b5342364ee32897cecc1bb519d6eb030e46381511585322;
            proofs[0][13] = 0xf6374e327c579637c9875136181c1f1c4f0e393a9da4032c6eeb81c1bb3ee408;
            proofs[0][14] = 0xcd9c1998ac7b7a192b2637f1d5a5e7d1f9ad71e9ea55e162344b04c197b5f2bb;
            proofs[0][15] = 0x05aaa3525f73076e3a136f39647abc14e16d15518f5d0e55b73465d03a7b03aa;
            proofs[0][16] = 0x204960082c3c6243c6849fa313c963ec891dcf89502d913cce409c3f1de484a6;

            vm.prank(targetUser);
            MRD.claim(users, tokens, amounts, proofs);
            assertEq(TestLib.rEUL.balanceOf(targetUser), _before + amounts[0], "after");
        }

        // ** Withdraw EUL
        {
            assertEq(EUL.balanceOf(targetUser), 0, "before");
            uint256[] memory ts_array = TestLib.rEUL.getLockedAmountsLockTimestamps(targetUser);
            // console.log(TestLib.rEUL.getLockedAmountsLength(targetUser));

            vm.prank(targetUser);
            TestLib.rEUL.withdrawToByLockTimestamp(targetUser, ts_array[0], true);
            assertEq(EUL.balanceOf(targetUser), 34166215410558281480, "after"); // 20% of amount
        }
    }

    // wait till expiration and withdraw all 100%
    function test_rewards_euler_withdraw_all() public {
        vm.rollFork(22159144 + 1);
        vm.warp(block.timestamp + 180 days);

        // ** Withdraw EUL now
        {
            assertEq(TestLib.rEUL.balanceOf(targetUser), 170831077052791407402, "before");
            assertEq(EUL.balanceOf(targetUser), 0, "before");
            uint256[] memory ts_array = TestLib.rEUL.getLockedAmountsLockTimestamps(targetUser);

            vm.prank(targetUser);
            TestLib.rEUL.withdrawToByLockTimestamp(targetUser, ts_array[0], true);
            assertEq(TestLib.rEUL.balanceOf(targetUser), 0, "after");
            assertEq(EUL.balanceOf(targetUser), 170831077052791407402, "after");
        }
    }

    // claim all rewards, wait till expiration and withdraw all 100%
    function test_rewards_euler_claim_real_time_api() public {
        vm.rollFork(22469023);
        create_accounts_and_tokens(TestLib.USDC, 6, "USDC", TestLib.WETH, 18, "WETH");

        // ** Claim rEUL
        {
            uint256 _before = TestLib.rEUL.balanceOf(targetUser);
            assertEq(_before, 170831077052791407402, "before");

            address[] memory users = new address[](1);
            users[0] = targetUser;
            address[] memory tokens = new address[](1);
            tokens[0] = address(TestLib.rEUL);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 183012673785523122481;

            bytes32[][] memory proofs = new bytes32[][](1);
            proofs[0] = new bytes32[](17);
            proofs[0][0] = 0xc41888d0709f07a669eaa5faecc34122980bd31f12a174eb9bc6ab3a1b46811e;
            proofs[0][1] = 0xcbd6fcb1edc26be5f993430ebdd225ee4ab9148280227b822462d63bccd104b4;
            proofs[0][2] = 0x95a844c3374d23df5864e5b57a0fd6952d006bd007456071b330bf88ea1f69ad;
            proofs[0][3] = 0x36a5449131ad0de781ce6b1ed1290be4e4738b2c9f334b1a4cb5dd72ddd9d72b;
            proofs[0][4] = 0x658c96247131899680f129fd9faf0ebc91c7e96f92b6c1521dfece04e7626c9d;
            proofs[0][5] = 0xef23774ec82376d997add4e975a2ce63957d807f5f01e907cc7565dd064659be;
            proofs[0][6] = 0xb2a2a1d3727fc51271bb69fee0c8954cea689042def2f9ce541f59e66a7d7f95;
            proofs[0][7] = 0x3f1ccc91eeb8340706effde92d6ad25e4195e3519ab0981924b4cde257f5ad38;
            proofs[0][8] = 0xd8e7b65a1ba4d2819aa0a77d101bf16733303714c0dbd9f27bd61d4ffe3de6a8;
            proofs[0][9] = 0xcfb8d5c3ed51f181eeab26187044ab0c3a77deb92acae7620e60a3036b0a3c98;
            proofs[0][10] = 0xe937419e21151ac6af6e88b57fdad190ed6d881a0ad6828f9cf6f2bbe9ac0411;
            proofs[0][11] = 0xe514384d70b9861bebd2b74085f1968ee9f2aa24ac547ffe875328f98d367e8c;
            proofs[0][12] = 0x5577cb0bbc8b33547213ef7d02c673e733a7511e087419a1520f68dd522065ba;
            proofs[0][13] = 0xdbefa1764e7efb93b6ab6d76c2805ef2511d1375896e0a6efc0bd6c13631f5e2;
            proofs[0][14] = 0xfd86d3602cca59a38b98e226d197d7b483fa1d92f21fe57fedd427362eb6612a;
            proofs[0][15] = 0xd863ad147b0712f2234d1f7356e6b161bee349c46959257b25df57662aa68c3e;
            proofs[0][16] = 0xbdd747754cb18abed8ca91f8611001a7399a29f86aaa63b1768d41104455e54f;

            vm.prank(targetUser);
            MRD.claim(users, tokens, amounts, proofs);
            assertEq(TestLib.rEUL.balanceOf(targetUser), amounts[0], "after");
        }

        // ** Withdraw EUL
        {
            vm.warp(block.timestamp + 180 days);
            assertEq(EUL.balanceOf(targetUser), 0, "before");
            // console.log(TestLib.rEUL.getLockedAmountsLength(targetUser));
            uint256[] memory ts_array = TestLib.rEUL.getLockedAmountsLockTimestamps(targetUser);

            vm.prank(targetUser);
            TestLib.rEUL.withdrawToByLockTimestamp(targetUser, ts_array[0], true);
            vm.prank(targetUser);
            TestLib.rEUL.withdrawToByLockTimestamp(alice.addr, ts_array[1], true);

            assertEq(EUL.balanceOf(targetUser), 170831077052791407402, "after"); // 20% of amount
            assertEq(EUL.balanceOf(alice.addr), 12181596732731715079, "after"); // 20% of amount
        }
    }

    // recreate reward claim
    function test_rewards_morpho_recreate_claims() public {
        vm.rollFork(22476376 - 1);
        targetUser = 0xeA6b2398715d161E36CA905B7526f27f2167e4D7;

        uint256 amount = 30151918784160194072;
        assertEq(MORPHO.balanceOf(targetUser), 0, "before");

        bytes32[] memory proof = new bytes32[](16);
        proof[0] = 0x302ac0237181fdc70530e69cdda68df1b7ce4853c1f30d8d289da066db747f8f;
        proof[1] = 0x019af3d57e57c6e4899a18809550492d9883183f95b8a663f7fddbee5999ab5e;
        proof[2] = 0x25b6f540749339427b09eb627ee9015cb64eb48ee4e4874d9e6e5a1449331c1a;
        proof[3] = 0x8ed6f889f17575162ab4c855612e313e2196c9a62416144257c8a36f2e203d8b;
        proof[4] = 0xf52eb7bd7655ac6c377246e269f9cca261378d7eb0521ea8b6cb658fe3fa5e5c;
        proof[5] = 0xfc2d7993c955522105b30e1f43ae7095087caae6bf0167230a1d2647c607640f;
        proof[6] = 0xb04664b51984c1c46238c5e53a2a1992a589f3e7ad7731f083685a75d478ed2e;
        proof[7] = 0x0a3865822187340d179fbae7ea9940297937ce11c45d4ecee8581ccea251409f;
        proof[8] = 0xe06253bf323e1e9227519b578f4fbb21531dc8bcb070aa2d9e13f48b90783ec5;
        proof[9] = 0xea961dc447ad659618ebe693405c94628d7cc26803166b6b7919111a13f20820;
        proof[10] = 0x28edd623369a7f0c037aa1c4507c4292a31dade7d844f33c3d7eb20bb0ddffb3;
        proof[11] = 0xdca12b9a0d55483b8eaa8730a26218a0459ef02ee1ed18ead9c056dc6e29273c;
        proof[12] = 0x6e175ba91e044be13bd943bf157a24f0458bd539198c246ba4f890303860f94e;
        proof[13] = 0x7fc9f0ec119adb249b132c7923ae4e205fd23f41f14bba765eb55ec8318522c8;
        proof[14] = 0xdb60e0665911b5f78bc64bffefcfea906f4e3f267aebf122d1b555fda457640a;
        proof[15] = 0xc0b1eba0d78e59ed4b049d5c20ee2d8947839898865d1d2a528f5c6373e34b3e;

        vm.prank(targetUser);
        URD.claim(targetUser, address(MORPHO), amount, proof);
        assertEq(MORPHO.balanceOf(targetUser), 8725665134517793063, "after");
    }

    // ** Helpers

    function _verifyProof(
        address user,
        address token,
        uint256 amount,
        bytes32[] memory proof
    ) internal pure returns (bytes32 currentHash) {
        bytes32 leaf = keccak256(abi.encode(user, token, amount));
        currentHash = leaf;
        uint256 proofLength = proof.length;
        for (uint256 i; i < proofLength; ) {
            if (currentHash < proof[i]) {
                currentHash = keccak256(abi.encode(currentHash, proof[i]));
            } else {
                currentHash = keccak256(abi.encode(proof[i], currentHash));
            }
            unchecked {
                ++i;
            }
        }
    }
}
