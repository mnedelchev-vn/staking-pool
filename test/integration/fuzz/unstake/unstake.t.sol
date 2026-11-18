// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Modifiers} from "../../../utils/Modifiers.sol";

contract Unstake_Integration_Fuzz_Test is Modifiers {
    uint256 internal constant MAX = 1_000_000_000e18;

    /// @notice With other stakers present, unstaking pays exactly `amount - floor(amount * unstakingFee / 10_000)`
    /// plus the pending reward. The stake and the total stakes drop by the GROSS amount: the fee leaves the payout,
    /// not the bookkeeping, and stays in the pool for the remaining stakers.
    /// @dev Complements `testFuzz_stakeFeeExact` (stake side only) and `testFuzz_roundtripNeverProfits` (an
    /// inequality). The staking fee is non-zero here while the unstaking fee is fuzzed, so mixing the two up fails.
    function testFuzz_Unstake_ChargesExactFee(
        uint256 bobStake,
        uint256 aliceStake,
        uint256 donation,
        uint256 amount,
        uint16 unstakingFee
    )
        external
    {
        bobStake = bound(bobStake, 1 ether, MAX);
        aliceStake = bound(aliceStake, 1 ether, MAX);
        donation = bound(donation, 1 ether, MAX);
        unstakingFee = uint16(bound(unstakingFee, 0, MAX_FEE));

        vm.prank(owner);
        sp.setFees(STAKING_FEE, unstakingFee);

        // bob stays in the pool for the whole test, so the unstaking fee is always charged.
        _stake(bob, bobStake);
        _stake(alice, aliceStake);
        _donate(carol, donation);

        uint256 aliceStaked = _stakedOf(alice);
        amount = bound(amount, 1, aliceStaked);

        uint256 pending = sp.getPendingReward(alice);
        uint256 expectedFee = _fee(amount, unstakingFee);
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 totalStakesBefore = sp.totalStakes();

        _unstake(alice, amount);

        assertEq(token.balanceOf(alice), aliceBalanceBefore + amount - expectedFee + pending, "alice payout");
        assertEq(_stakedOf(alice), aliceStaked - amount, "alice stake drops by the gross amount");
        assertEq(sp.totalStakes(), totalStakesBefore - amount, "totalStakes drops by the gross amount");
    }
}
