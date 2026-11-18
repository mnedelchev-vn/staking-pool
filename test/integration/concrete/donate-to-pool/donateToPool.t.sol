// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {StakingPool} from "../../../../contracts/StakingPool.sol";
import {Modifiers} from "../../../utils/Modifiers.sol";

contract DonateToPool_Integration_Concrete_Test is Modifiers {
    uint256 internal constant DONATION = 10_000e18;

    function test_RevertGiven_Paused() external {
        // Stakes exist, so the pause (not InvalidInject) is the reason for the revert.
        _stakeAliceThenBob();
        _pause();
        _approve(carol, DONATION);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(carol);
        sp.donateToPool(DONATION);
    }

    function test_RevertGiven_NoStakesInPool() external givenNotPaused {
        _approve(carol, DONATION);

        vm.expectRevert(StakingPool.InvalidInject.selector);
        vm.prank(carol);
        sp.donateToPool(DONATION);
    }

    function test_RevertGiven_InsufficientAllowance() external givenNotPaused givenTwoStakers {
        _approve(carol, DONATION - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(sp), DONATION - 1, DONATION
            )
        );
        vm.prank(carol);
        sp.donateToPool(DONATION);
    }

    function test_WhenAmountZero() external givenNotPaused givenTwoStakers {
        uint256 carolBalanceBefore = token.balanceOf(carol);

        vm.prank(carol);
        sp.donateToPool(0);

        // It should not move tokens or change the dividends.
        assertEq(token.balanceOf(carol), carolBalanceBefore, "carol balance");
        assertEq(token.balanceOf(address(sp)), POOL_BALANCE_AFTER_SECOND, "pool balance");
        assertEq(sp.totalDividends(), DIVIDEND_PER_TOKEN_AFTER_SECOND, "totalDividends");
        assertEq(sp.getPendingReward(alice), ALICE_PENDING_AFTER_SECOND, "alice pending");
        assertEq(sp.getPendingReward(bob), BOB_PENDING_AFTER_SECOND, "bob pending");
    }

    function test_WhenAmountNotZero() external givenNotPaused givenTwoStakers {
        uint256 carolBalanceBefore = token.balanceOf(carol);
        _approve(carol, DONATION);

        // It should emit {Payout} event.
        // NOTE: Payout.round is the round AFTER the increment (round 2 -> 3).
        vm.expectEmit(address(sp));
        emit StakingPool.Payout(3, DONATION, carol);

        vm.prank(carol);
        sp.donateToPool(DONATION);

        // It should pull the tokens into the pool.
        assertEq(token.balanceOf(carol), carolBalanceBefore - DONATION, "carol balance");
        assertEq(token.balanceOf(address(sp)), POOL_BALANCE_AFTER_SECOND + DONATION, "pool balance");
        // It should not credit a stake to the donor.
        assertEq(_stakedOf(carol), 0, "carol stake");
        assertEq(sp.totalStakes(), TOTAL_STAKES_AFTER_SECOND, "totalStakes");
        // It should raise every staker's reward pro rata:
        // dividendPerToken += 10_000e18 * 1e18 / 50_000e18 = 2e17
        assertEq(sp.round(), 3, "round");
        assertEq(sp.totalDividends(), 2.2e17, "totalDividends");
        assertEq(sp.payouts(2), 2.2e17, "payouts[2]");
        assertEq(sp.getPendingReward(alice), 220e18, "alice pending: 20 + 1_000/50_000 * 10_000");
        assertEq(sp.getPendingReward(bob), 10_780e18, "bob pending: 980 + 49_000/50_000 * 10_000");
    }
}
