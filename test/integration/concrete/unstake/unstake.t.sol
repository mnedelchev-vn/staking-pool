// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StakingPool} from "../../../../contracts/StakingPool.sol";
import {Modifiers} from "../../../utils/Modifiers.sol";

contract Unstake_Integration_Concrete_Test is Modifiers {
    /// bob unstakes 20_000 of his 49_000: fee = 3% = 600, total stakes after = 30_000 -> dividendPerToken += 2e16
    uint256 internal constant BOB_UNSTAKE = 20_000e18;
    uint256 internal constant BOB_UNSTAKE_FEE = 600e18;
    uint256 internal constant BOB_UNSTAKE_NET = 19_400e18;

    function test_RevertWhen_AmountZero() external {
        _stake(alice, FIRST_STAKE);

        vm.expectRevert(StakingPool.InvalidAmount.selector);
        vm.prank(alice);
        sp.unstake(0);
    }

    function test_RevertWhen_CallerNeverStaked() external whenAmountNotZero {
        _stakeAliceThenBob();

        vm.expectRevert(StakingPool.InvalidAmount.selector);
        vm.prank(dave);
        sp.unstake(1);
    }

    function test_RevertWhen_AmountExceedsStakedBalance() external whenAmountNotZero {
        _stakeAliceThenBob();

        // One wei over the staked balance.
        vm.expectRevert(StakingPool.InvalidAmount.selector);
        vm.prank(alice);
        sp.unstake(FIRST_STAKE + 1);
    }

    function test_GivenCallerIsTheLastStaker() external whenAmountNotZero whenAmountWithinStakedBalance {
        _stake(alice, FIRST_STAKE);
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // It should emit {Unstaked} event. The unstaking fee is 3%, yet the last staker pays none.
        vm.expectEmit(address(sp));
        emit StakingPool.Unstaked(alice, FIRST_STAKE, 0);

        vm.prank(alice);
        sp.unstake(FIRST_STAKE);

        // It should return the full amount without a fee.
        assertEq(token.balanceOf(alice), aliceBalanceBefore + FIRST_STAKE, "alice balance");
        // It should clear the staker balance.
        assertEq(_stakedOf(alice), 0, "alice stake");
        assertEq(sp.totalStakes(), 0, "totalStakes");
        // It should not open a payout round.
        assertEq(sp.round(), 1, "round");
        assertEq(sp.totalDividends(), 0, "totalDividends");
    }

    function test_GivenPaused()
        external
        whenAmountNotZero
        whenAmountWithinStakedBalance
        givenOtherStakersRemain
    {
        _pause();
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Only stake() and donateToPool() are pausable, exits stay open.
        _unstake(alice, FIRST_STAKE);

        // 1_000 - 3% fee (30) + pending reward (20)
        assertEq(token.balanceOf(alice), aliceBalanceBefore + 990e18, "alice balance");
        assertEq(_stakedOf(alice), 0, "alice stake");
    }

    function test_GivenUnstakingFeeZero()
        external
        whenAmountNotZero
        whenAmountWithinStakedBalance
        givenOtherStakersRemain
    {
        vm.prank(owner);
        sp.setFees(STAKING_FEE, 0);
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        vm.expectEmit(address(sp));
        emit StakingPool.Unstaked(alice, FIRST_STAKE, 0);
        _unstake(alice, FIRST_STAKE);

        // It should return the full amount plus the pending reward.
        assertEq(token.balanceOf(alice), aliceBalanceBefore + FIRST_STAKE + ALICE_PENDING_AFTER_SECOND, "alice balance");
        assertEq(sp.totalDividends(), DIVIDEND_PER_TOKEN_AFTER_SECOND, "no new dividends");
        assertEq(sp.totalStakes(), SECOND_STAKE_NET, "totalStakes");
    }

    function test_GivenFeeRoundsDownToZero()
        external
        whenAmountNotZero
        whenAmountWithinStakedBalance
        givenOtherStakersRemain
    {
        // 33 * 3% = 0.99 -> floors to 0
        uint256 dust = 33;
        assertEq(_fee(dust, UNSTAKING_FEE), 0, "test premise: fee floors to zero");
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        vm.expectEmit(address(sp));
        emit StakingPool.Unstaked(alice, dust, 0);
        _unstake(alice, dust);

        // It should return the full amount plus the pending reward.
        assertEq(token.balanceOf(alice), aliceBalanceBefore + dust + ALICE_PENDING_AFTER_SECOND, "alice balance");
        assertEq(_stakedOf(alice), FIRST_STAKE - dust, "alice stake");
        assertEq(sp.totalDividends(), DIVIDEND_PER_TOKEN_AFTER_SECOND, "no new dividends");
    }

    function test_GivenStakerHasNoPendingReward()
        external
        whenAmountNotZero
        whenAmountWithinStakedBalance
        givenOtherStakersRemain
    {
        _claim(bob);
        assertEq(sp.getPendingReward(bob), 0, "test premise");
        uint256 bobBalanceBefore = token.balanceOf(bob);
        uint256 poolBalanceBefore = token.balanceOf(address(sp));

        // It should emit {Payout} and {Unstaked} events.
        // NOTE: Payout.round is the round AFTER the increment (round 2 -> 3).
        vm.expectEmit(address(sp));
        emit StakingPool.Payout(3, BOB_UNSTAKE_FEE, bob);
        vm.expectEmit(address(sp));
        emit StakingPool.Unstaked(bob, BOB_UNSTAKE_NET, BOB_UNSTAKE_FEE);

        vm.prank(bob);
        sp.unstake(BOB_UNSTAKE);

        // It should transfer the amount minus the fee.
        assertEq(token.balanceOf(bob), bobBalanceBefore + BOB_UNSTAKE_NET, "bob balance");
        assertEq(token.balanceOf(address(sp)), poolBalanceBefore - BOB_UNSTAKE_NET, "pool balance");
        // It should reduce the stake and the total stakes by the full amount (the fee leaves the payout, not the stake).
        assertEq(_stakedOf(bob), SECOND_STAKE_NET - BOB_UNSTAKE, "bob stake");
        assertEq(sp.totalStakes(), TOTAL_STAKES_AFTER_SECOND - BOB_UNSTAKE, "totalStakes");
        // It should open a payout round with the fee.
        assertEq(sp.round(), 3, "round");
        assertEq(sp.totalDividends(), 4e16, "totalDividends");
        assertEq(sp.payouts(2), 4e16, "payouts[2]");
        // bob keeps earning on what is left: 2e16 * 29_000. alice: 20 (old) + 2e16 * 1_000.
        assertEq(sp.getPendingReward(bob), 580e18, "bob pending");
        assertEq(sp.getPendingReward(alice), 40e18, "alice pending");
        assertEq(
            token.balanceOf(address(sp)),
            sp.totalStakes() + sp.getPendingReward(alice) + sp.getPendingReward(bob),
            "pool balance decomposition"
        );
    }

    function test_GivenStakerHasPendingReward()
        external
        whenAmountNotZero
        whenAmountWithinStakedBalance
        givenOtherStakersRemain
    {
        uint256 bobBalanceBefore = token.balanceOf(bob);

        // It should emit {Payout}, {ClaimReward} and {Unstaked} events.
        vm.expectEmit(address(sp));
        emit StakingPool.Payout(3, BOB_UNSTAKE_FEE, bob);
        vm.expectEmit(address(sp));
        emit StakingPool.ClaimReward(bob, BOB_PENDING_AFTER_SECOND);
        vm.expectEmit(address(sp));
        emit StakingPool.Unstaked(bob, BOB_UNSTAKE_NET, BOB_UNSTAKE_FEE);

        vm.prank(bob);
        sp.unstake(BOB_UNSTAKE);

        // It should transfer the amount minus the fee plus the reward.
        assertEq(token.balanceOf(bob), bobBalanceBefore + BOB_UNSTAKE_NET + BOB_PENDING_AFTER_SECOND, "bob balance");
        assertEq(_stakedOf(bob), SECOND_STAKE_NET - BOB_UNSTAKE, "bob stake");
        assertEq(sp.totalStakes(), TOTAL_STAKES_AFTER_SECOND - BOB_UNSTAKE, "totalStakes");
        // The reward was settled during the unstake, only the share of the new fee is left.
        assertEq(sp.getPendingReward(bob), 580e18, "bob pending");
        assertEq(sp.getPendingReward(alice), 40e18, "alice pending");
        assertEq(
            token.balanceOf(address(sp)),
            sp.totalStakes() + sp.getPendingReward(alice) + sp.getPendingReward(bob),
            "pool balance decomposition"
        );
    }
}
