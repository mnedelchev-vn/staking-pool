// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Modifiers} from "../../../utils/Modifiers.sol";

contract GetPendingReward_Integration_Concrete_Test is Modifiers {
    function test_GivenAccountNeverStaked() external {
        _stakeAliceThenBob();

        assertEq(sp.getPendingReward(dave), 0, "dave pending");
    }

    function test_GivenAccountIsTheOnlyStaker() external {
        // The first staker pays no fee and no payout exists yet.
        _stake(alice, FIRST_STAKE);

        assertEq(sp.getPendingReward(alice), 0, "alice pending");
    }

    function test_GivenAccountFullyUnstaked() external {
        _stakeAliceThenBob();
        _unstake(alice, FIRST_STAKE);

        assertEq(sp.getPendingReward(alice), 0, "alice pending");
    }

    function test_GivenNoPayoutSinceTheLastInteraction() external givenTwoStakers {
        _claim(alice);

        assertEq(sp.getPendingReward(alice), 0, "alice pending");
        // Claiming only moves alice's own marker, bob's reward is untouched.
        assertEq(sp.getPendingReward(bob), BOB_PENDING_AFTER_SECOND, "bob pending");
    }

    function test_GivenPayoutsSinceTheLastInteraction() external givenTwoStakers {
        // Entry-fee payout of the second stake: 2e16 per staked token.
        assertEq(sp.getPendingReward(alice), ALICE_PENDING_AFTER_SECOND, "alice pending after entry fee");
        assertEq(sp.getPendingReward(bob), BOB_PENDING_AFTER_SECOND, "bob pending after entry fee");

        // A further 10_000 donation adds 2e17 per staked token: +200 for alice (1_000), +9_800 for bob (49_000).
        _donate(carol, 10_000e18);

        assertEq(sp.getPendingReward(alice), 220e18, "alice pending after donation");
        assertEq(sp.getPendingReward(bob), 10_780e18, "bob pending after donation");
    }
}
