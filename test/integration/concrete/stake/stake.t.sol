// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {StakingPool} from "../../../../contracts/StakingPool.sol";
import {Modifiers} from "../../../utils/Modifiers.sol";

contract Stake_Integration_Concrete_Test is Modifiers {
    function test_RevertGiven_Paused() external {
        _pause();
        // Allowance is in place, so the pause is the only reason for the revert.
        _approve(alice, FIRST_STAKE);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        sp.stake(FIRST_STAKE);
    }

    function test_RevertWhen_AmountZero() external givenNotPaused {
        vm.expectRevert(StakingPool.InvalidAmount.selector);
        vm.prank(alice);
        sp.stake(0);
    }

    function test_RevertGiven_InsufficientAllowance() external givenNotPaused whenAmountNotZero {
        _approve(alice, FIRST_STAKE - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(sp), FIRST_STAKE - 1, FIRST_STAKE
            )
        );
        vm.prank(alice);
        sp.stake(FIRST_STAKE);
    }

    function test_RevertGiven_InsufficientBalance() external givenNotPaused whenAmountNotZero {
        // dave holds no tokens.
        _approve(dave, FIRST_STAKE);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, dave, 0, FIRST_STAKE)
        );
        vm.prank(dave);
        sp.stake(FIRST_STAKE);
    }

    function test_GivenFreshPool()
        external
        givenNotPaused
        whenAmountNotZero
        givenSufficientAllowanceAndBalance
    {
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        _approve(alice, FIRST_STAKE);

        // It should emit {Staked} event. The staking fee is 2%, yet the first staker pays none.
        vm.expectEmit(address(sp));
        emit StakingPool.Staked(alice, FIRST_STAKE, 0);

        vm.prank(alice);
        sp.stake(FIRST_STAKE);

        // It should set the staker balance to the amount.
        assertEq(_stakedOf(alice), FIRST_STAKE, "staker balance");
        assertEq(_roundOf(alice), 1, "staker round");
        assertEq(sp.totalStakes(), FIRST_STAKE, "totalStakes");
        // It should not open a payout round.
        assertEq(sp.round(), 1, "round");
        assertEq(sp.totalDividends(), 0, "totalDividends");
        assertEq(sp.scaledRemainder(), 0, "scaledRemainder");
        // It should pull the tokens into the pool.
        assertEq(token.balanceOf(address(sp)), FIRST_STAKE, "pool balance");
        assertEq(token.balanceOf(alice), aliceBalanceBefore - FIRST_STAKE, "alice balance");
    }

    function test_GivenPoolEmptiedByEarlierStakers()
        external
        givenNotPaused
        whenAmountNotZero
        givenSufficientAllowanceAndBalance
    {
        // Run the pool through a full cycle so dividends exist, then everybody leaves.
        _stakeAliceThenBob();
        _unstake(alice, _stakedOf(alice));
        _unstake(bob, _stakedOf(bob));
        assertEq(sp.totalStakes(), 0, "pool must be empty");
        uint256 roundBefore = sp.round();
        uint256 dividendsBefore = sp.totalDividends();
        assertGt(dividendsBefore, 0, "past dividends must exist");

        // carol is the first staker of an empty pool again.
        _approve(carol, FIRST_STAKE);
        vm.expectEmit(address(sp));
        emit StakingPool.Staked(carol, FIRST_STAKE, 0);
        vm.prank(carol);
        sp.stake(FIRST_STAKE);

        // It should credit the full amount without a fee or past dividends.
        assertEq(_stakedOf(carol), FIRST_STAKE, "staker balance");
        assertEq(sp.totalStakes(), FIRST_STAKE, "totalStakes");
        assertEq(sp.round(), roundBefore, "no payout round opened");
        assertEq(sp.totalDividends(), dividendsBefore, "dividends untouched");
        assertEq(sp.getPendingReward(carol), 0, "no historic reward");
    }

    function test_GivenFeeRoundsDownToZero()
        external
        givenNotPaused
        whenAmountNotZero
        givenSufficientAllowanceAndBalance
        givenStakesInPool
    {
        // 49 * 2% = 0.98 -> floors to 0
        uint256 dust = 49;
        assertEq(_fee(dust, STAKING_FEE), 0, "test premise: fee floors to zero");

        _approve(bob, dust);
        vm.expectEmit(address(sp));
        emit StakingPool.Staked(bob, dust, 0);
        vm.prank(bob);
        sp.stake(dust);

        // It should credit the full amount without opening a payout round.
        assertEq(_stakedOf(bob), dust, "staker balance");
        assertEq(sp.totalStakes(), FIRST_STAKE + dust, "totalStakes");
        assertEq(sp.round(), 1, "round");
        assertEq(sp.totalDividends(), 0, "totalDividends");
        assertEq(token.balanceOf(address(sp)), FIRST_STAKE + dust, "pool balance");
    }

    function test_GivenStakerHasNoPendingReward()
        external
        givenNotPaused
        whenAmountNotZero
        givenSufficientAllowanceAndBalance
        givenStakesInPool
    {
        uint256 bobBalanceBefore = token.balanceOf(bob);
        _approve(bob, SECOND_STAKE);

        // It should emit {Payout} and {Staked} events.
        // NOTE: Payout.round is the round AFTER the increment (payouts[1] is written, the event says 2).
        vm.expectEmit(address(sp));
        emit StakingPool.Payout(2, SECOND_STAKE_FEE, bob);
        vm.expectEmit(address(sp));
        emit StakingPool.Staked(bob, SECOND_STAKE_NET, SECOND_STAKE_FEE);

        vm.prank(bob);
        sp.stake(SECOND_STAKE);

        // It should credit the amount minus the fee.
        assertEq(_stakedOf(bob), SECOND_STAKE_NET, "staker balance");
        assertEq(_roundOf(bob), 1, "staker round is the round it joined in");
        assertEq(sp.totalStakes(), TOTAL_STAKES_AFTER_SECOND, "totalStakes");
        assertEq(token.balanceOf(bob), bobBalanceBefore - SECOND_STAKE, "bob pays the gross amount");
        // It should open a payout round with the fee.
        assertEq(sp.round(), 2, "round");
        assertEq(sp.totalDividends(), DIVIDEND_PER_TOKEN_AFTER_SECOND, "totalDividends");
        assertEq(sp.payouts(1), DIVIDEND_PER_TOKEN_AFTER_SECOND, "payouts[1]");
        assertEq(sp.scaledRemainder(), 0, "scaledRemainder");
        assertEq(token.balanceOf(address(sp)), POOL_BALANCE_AFTER_SECOND, "the fee stays in the pool");
        // The fee is split pro rata over ALL stakes, alice's and bob's own.
        assertEq(sp.getPendingReward(alice), ALICE_PENDING_AFTER_SECOND, "alice share of the fee");
        // It should share the fee with the new staker too.
        assertEq(sp.getPendingReward(bob), BOB_PENDING_AFTER_SECOND, "bob share of his own fee");
    }

    function test_GivenStakerHasPendingReward()
        external
        givenNotPaused
        whenAmountNotZero
        givenSufficientAllowanceAndBalance
        givenStakesInPool
    {
        // The pool is now at "two stakers"; alice's pending reward is 20e18.
        _stake(bob, SECOND_STAKE);
        assertEq(sp.getPendingReward(alice), ALICE_PENDING_AFTER_SECOND, "test premise");

        // 2% of 2_500_000 = 50_000 fee, net 2_450_000, new total stakes 2_500_000 -> dividendPerToken = 2e16 again.
        uint256 topUp = 2_500_000e18;
        uint256 topUpFee = 50_000e18;
        uint256 topUpNet = 2_450_000e18;
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        _approve(alice, topUp);

        // It should emit {Payout}, {ClaimReward} and {Staked} events.
        vm.expectEmit(address(sp));
        emit StakingPool.Payout(3, topUpFee, alice);
        vm.expectEmit(address(sp));
        emit StakingPool.ClaimReward(alice, ALICE_PENDING_AFTER_SECOND);
        vm.expectEmit(address(sp));
        emit StakingPool.Staked(alice, topUpNet, topUpFee);

        vm.prank(alice);
        sp.stake(topUp);

        // It should transfer the pending reward to the staker.
        assertEq(token.balanceOf(alice), aliceBalanceBefore - topUp + ALICE_PENDING_AFTER_SECOND, "alice net cash flow");
        // It should credit the amount minus the fee on top of the old stake.
        assertEq(_stakedOf(alice), FIRST_STAKE + topUpNet, "alice stake");
        assertEq(sp.totalStakes(), 2_500_000e18, "totalStakes");
        assertEq(sp.round(), 3, "round");
        assertEq(sp.totalDividends(), 4e16, "totalDividends");
        // The old reward was settled, only the share of the new fee is pending now: 2e16 * 2_451_000.
        assertEq(sp.getPendingReward(alice), 49_020e18, "alice pending after top-up");
        // bob's still-unclaimed 980e18 plus his share (2e16 * 49_000) of the second fee.
        assertEq(sp.getPendingReward(bob), 1_960e18, "bob pending");
        // Everything the pool holds is accounted for: principal + both pending rewards, no dust here.
        assertEq(
            token.balanceOf(address(sp)),
            sp.totalStakes() + sp.getPendingReward(alice) + sp.getPendingReward(bob),
            "pool balance decomposition"
        );
    }
}
