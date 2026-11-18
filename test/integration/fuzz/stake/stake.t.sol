// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Modifiers} from "../../../utils/Modifiers.sol";

contract Stake_Integration_Fuzz_Test is Modifiers {
    uint256 internal constant MAX = 1_000_000_000e18;

    /// @notice Topping up an existing position settles the pending reward exactly once: the staker's net cash flow is
    /// `-topUp + pendingBefore`, the stake grows by `topUp - fee`, and afterwards only a share of the staker's OWN
    /// entry fee (plus carried rounding dust) is pending.
    /// @dev The existing `_stake` helper in the unit suite only asserts inequalities on these balances.
    function testFuzz_Stake_TopUpSettlesPendingRewardExactly(
        uint256 aliceStake,
        uint256 bobStake,
        uint256 donation,
        uint256 topUp,
        uint16 stakingFee
    )
        external
    {
        aliceStake = bound(aliceStake, 1 ether, MAX);
        bobStake = bound(bobStake, 1 ether, MAX);
        donation = bound(donation, 1 ether, MAX);
        topUp = bound(topUp, 1, MAX);
        stakingFee = uint16(bound(stakingFee, 0, MAX_FEE));

        vm.prank(owner);
        sp.setFees(stakingFee, UNSTAKING_FEE);

        _stake(alice, aliceStake);
        _stake(bob, bobStake);
        _donate(carol, donation);

        uint256 pendingBefore = sp.getPendingReward(alice);
        uint256 stakedBefore = _stakedOf(alice);
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 fee = _fee(topUp, stakingFee);

        _stake(alice, topUp);

        assertEq(token.balanceOf(alice), aliceBalanceBefore - topUp + pendingBefore, "alice net cash flow");
        assertEq(_stakedOf(alice), stakedBefore + topUp - fee, "alice stake grows by the net amount");
        // Her own fee, plus rounding dust that earlier payouts left in `scaledRemainder` and this payout carries over
        // (strictly less than totalStakes / SCALING tokens, the same tolerance the unit-level donation fuzz uses).
        assertLe(
            sp.getPendingReward(alice),
            fee + sp.totalStakes() / SCALING + 1,
            "only her own fee share and carried dust can be pending"
        );
        assertGe(
            token.balanceOf(address(sp)),
            sp.totalStakes() + sp.getPendingReward(alice) + sp.getPendingReward(bob),
            "pool stays solvent"
        );
    }
}
