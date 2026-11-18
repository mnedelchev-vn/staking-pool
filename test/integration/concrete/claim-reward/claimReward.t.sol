// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StakingPool} from "../../../../contracts/StakingPool.sol";
import {Modifiers} from "../../../utils/Modifiers.sol";

contract ClaimReward_Integration_Concrete_Test is Modifiers {
    function test_RevertWhen_CallerNeverStaked() external givenNoPendingReward {
        // Others are staked and rewards exist, but dave holds no stake.
        _stakeAliceThenBob();

        vm.expectRevert(StakingPool.InvalidRewardClaim.selector);
        vm.prank(dave);
        sp.claimReward();
    }

    function test_RevertWhen_CallerIsOnlyStaker() external givenNoPendingReward {
        // No fee was ever charged, so no payout exists.
        _stake(alice, FIRST_STAKE);

        vm.expectRevert(StakingPool.InvalidRewardClaim.selector);
        vm.prank(alice);
        sp.claimReward();
    }

    function test_GivenPaused() external givenPendingReward {
        _pause();
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Only stake() and donateToPool() are pausable, rewards stay claimable.
        _claim(alice);

        assertEq(token.balanceOf(alice), aliceBalanceBefore + ALICE_PENDING_AFTER_SECOND, "reward paid while paused");
    }

    function test_GivenNotPaused() external givenPendingReward givenNotPaused {
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 poolBalanceBefore = token.balanceOf(address(sp));

        // It should emit {ClaimReward} event.
        vm.expectEmit(address(sp));
        emit StakingPool.ClaimReward(alice, ALICE_PENDING_AFTER_SECOND);

        vm.prank(alice);
        sp.claimReward();

        // It should transfer the reward to the staker.
        assertEq(token.balanceOf(alice), aliceBalanceBefore + ALICE_PENDING_AFTER_SECOND, "alice balance");
        assertEq(token.balanceOf(address(sp)), poolBalanceBefore - ALICE_PENDING_AFTER_SECOND, "pool balance");
        assertEq(sp.getPendingReward(alice), 0, "alice pending");
        // It should leave the staked amount unchanged.
        assertEq(_stakedOf(alice), FIRST_STAKE, "alice stake");
        assertEq(sp.totalStakes(), TOTAL_STAKES_AFTER_SECOND, "totalStakes");
        // It should move the staker to the current round.
        assertEq(_roundOf(alice), sp.round(), "alice round");
        // It should leave the other stakers' rewards unchanged.
        assertEq(sp.getPendingReward(bob), BOB_PENDING_AFTER_SECOND, "bob pending");
        // Claiming opens no payout round.
        assertEq(sp.round(), 2, "round");
        assertEq(sp.totalDividends(), DIVIDEND_PER_TOKEN_AFTER_SECOND, "totalDividends");
    }
}
