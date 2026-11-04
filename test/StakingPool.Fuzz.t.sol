// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {TestERC20} from "../contracts/mocks/TestERC20.sol";
import {StakingPool} from "../contracts/StakingPool.sol";

/// Stateless properties over arbitrary inputs.
contract StakingPoolFuzz is Test {
    TestERC20 token;
    StakingPool sp;
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    uint256 constant MAX = 1_000_000_000 ether;

    function setUp() public {
        vm.startPrank(owner);
        token = new TestERC20();
        sp = new StakingPool(address(token), 200, 200);
        token.mint(alice, MAX * 10);
        token.mint(bob, MAX * 10);
        token.mint(carol, MAX * 10);
        vm.stopPrank();
    }

    function _stake(address who, uint256 amt) internal {
        vm.startPrank(who);
        token.approve(address(sp), amt);
        sp.stake(amt);
        vm.stopPrank();
    }

    function _staked(address who) internal view returns (uint256 s) {
        (s,) = sp.stakers(who);
    }

    /// Roundtrip: a lone staker pays no fees and gets back exactly what they put in.
    function testFuzz_soloRoundtripIsExact(uint256 amt) public {
        amt = bound(amt, 1, MAX);
        uint256 before = token.balanceOf(alice);
        _stake(alice, amt);
        assertEq(_staked(alice), amt);
        vm.prank(alice);
        sp.unstake(amt);
        assertEq(token.balanceOf(alice), before);
        assertEq(token.balanceOf(address(sp)), 0);
    }

    /// No free money: with another staker present, stake-then-unstake never nets a profit.
    function testFuzz_roundtripNeverProfits(uint256 seed, uint256 amt, uint16 sFee, uint16 uFee) public {
        seed = bound(seed, 1, MAX);
        amt = bound(amt, 1, MAX);
        vm.startPrank(owner);
        sp.setFees(uint16(bound(sFee, 0, 1000)), uint16(bound(uFee, 0, 1000)));
        vm.stopPrank();

        _stake(bob, seed);

        uint256 before = token.balanceOf(alice);
        _stake(alice, amt);
        uint256 staked = _staked(alice);
        vm.prank(alice);
        sp.unstake(staked);
        // alice also receives any pending reward on exit, which is already included in her transfer
        assertLe(token.balanceOf(alice), before);
    }

    /// Fee exactness: the staking fee charged is floor(amt * fee / 10000) when others are staked.
    function testFuzz_stakeFeeExact(uint256 seed, uint256 amt, uint16 sFee) public {
        seed = bound(seed, 1, MAX);
        amt = bound(amt, 1, MAX);
        sFee = uint16(bound(sFee, 0, 1000));
        vm.prank(owner);
        sp.setFees(sFee, 0);

        _stake(bob, seed);
        uint256 expectedFee = (amt * sFee) / 10_000;
        uint256 totalBefore = sp.totalStakes();
        _stake(alice, amt);
        assertEq(_staked(alice), amt - expectedFee);
        assertEq(sp.totalStakes(), totalBefore + amt - expectedFee);
    }

    /// Idempotence: claiming twice in a row cannot pay twice.
    function testFuzz_claimIsIdempotent(uint256 a, uint256 b, uint256 donation) public {
        a = bound(a, 1 ether, MAX);
        b = bound(b, 1 ether, MAX);
        donation = bound(donation, 1 ether, MAX);

        _stake(alice, a);
        _stake(bob, b);
        vm.startPrank(carol);
        token.approve(address(sp), donation);
        sp.donateToPool(donation);
        vm.stopPrank();

        if (sp.getPendingReward(alice) == 0) return;
        vm.startPrank(alice);
        sp.claimReward();
        assertEq(sp.getPendingReward(alice), 0);
        vm.expectRevert(StakingPool.InvalidRewardClaim.selector);
        sp.claimReward();
        vm.stopPrank();
    }

    /// Fairness: a donation is split between stakers in proportion to stake,
    /// and the total handed out never exceeds the donation.
    function testFuzz_donationSplitProportionalAndBounded(uint256 a, uint256 b, uint256 donation) public {
        a = bound(a, 1 ether, MAX);
        b = bound(b, 1 ether, MAX);
        donation = bound(donation, 0, MAX);

        _stake(alice, a);
        _stake(bob, b);

        uint256 aliceBefore = sp.getPendingReward(alice);
        uint256 bobBefore = sp.getPendingReward(bob);

        vm.startPrank(carol);
        token.approve(address(sp), donation);
        sp.donateToPool(donation);
        vm.stopPrank();

        uint256 aliceGain = sp.getPendingReward(alice) - aliceBefore;
        uint256 bobGain = sp.getPendingReward(bob) - bobBefore;

        uint256 total = _staked(alice) + _staked(bob);
        // the delta may include scaledRemainder dust carried over from earlier fee payouts
        // (< totalStakes / SCALING tokens), but never more than that on top of the donation
        assertLe(aliceGain + bobGain, donation + total / sp.SCALING() + 1, "paid out more than donated");
        // dividendPerToken is floored at 1e-18/token, so allow stake/SCALING + 2 wei of deviation
        // (the remainder is carried to the next payout, not lost)
        uint256 tol = total / sp.SCALING() + 2;
        assertApproxEqAbs(aliceGain, (donation * _staked(alice)) / total, tol);
        assertApproxEqAbs(bobGain, (donation * _staked(bob)) / total, tol);
    }

    /// Time-of-entry: staking AFTER a donation earns nothing from it.
    function testFuzz_lateStakerGetsNothingFromPastDonation(uint256 a, uint256 b, uint256 donation) public {
        a = bound(a, 1 ether, MAX);
        b = bound(b, 1 ether, MAX);
        donation = bound(donation, 1 ether, MAX);

        _stake(alice, a);
        vm.startPrank(carol);
        token.approve(address(sp), donation);
        sp.donateToPool(donation);
        vm.stopPrank();

        vm.prank(owner);
        sp.setFees(0, 0); // isolate the donation from entry-fee payouts
        _stake(bob, b);
        assertEq(sp.getPendingReward(bob), 0);
    }

    /// Order independence: with fees off, who claims first does not change anyone's total.
    function testFuzz_claimOrderIrrelevant(uint256 a, uint256 b, uint256 donation) public {
        a = bound(a, 1 ether, MAX);
        b = bound(b, 1 ether, MAX);
        donation = bound(donation, 1 ether, MAX);

        _stake(alice, a);
        _stake(bob, b);
        vm.startPrank(carol);
        token.approve(address(sp), donation);
        sp.donateToPool(donation);
        vm.stopPrank();

        uint256 snap = vm.snapshotState();

        uint256 a1;
        uint256 b1;
        vm.prank(alice);
        try sp.claimReward() {} catch {}
        vm.prank(bob);
        try sp.claimReward() {} catch {}
        a1 = token.balanceOf(alice);
        b1 = token.balanceOf(bob);

        vm.revertToState(snap);

        vm.prank(bob);
        try sp.claimReward() {} catch {}
        vm.prank(alice);
        try sp.claimReward() {} catch {}
        assertEq(token.balanceOf(alice), a1);
        assertEq(token.balanceOf(bob), b1);
    }

    /// Cannot unstake more than staked, cannot unstake zero.
    function testFuzz_unstakeBounds(uint256 amt, uint256 extra) public {
        amt = bound(amt, 1, MAX);
        extra = bound(extra, 1, MAX);
        _stake(alice, amt);
        uint256 staked = _staked(alice);
        vm.startPrank(alice);
        vm.expectRevert(StakingPool.InvalidAmount.selector);
        sp.unstake(staked + extra);
        vm.expectRevert(StakingPool.InvalidAmount.selector);
        sp.unstake(0);
        vm.stopPrank();
    }

    /// Access control: no non-owner address can reach any owner-only function.
    function testFuzz_onlyOwnerFunctions(address caller, uint16 f1, uint16 f2, address tok, uint256 amt) public {
        vm.assume(caller != owner);
        vm.startPrank(caller);
        vm.expectRevert();
        sp.pause();
        vm.expectRevert();
        sp.unpause();
        vm.expectRevert();
        sp.setFees(f1, f2);
        vm.expectRevert();
        sp.recover(tok, amt);
        vm.stopPrank();
    }

    /// Fee cap: setFees accepts exactly the values <= 10%.
    function testFuzz_setFeesBoundary(uint16 s, uint16 u) public {
        vm.prank(owner);
        if (s > 1000 || u > 1000) {
            vm.expectRevert(StakingPool.InvalidFees.selector);
            sp.setFees(s, u);
        } else {
            sp.setFees(s, u);
            assertEq(sp.stakingFee(), s);
            assertEq(sp.unstakingFee(), u);
        }
    }

    /// recover() must never be able to drop the pool below staker principal.
    function testFuzz_recoverCannotTouchPrincipal(uint256 staked, uint256 stray, uint256 take) public {
        staked = bound(staked, 1, MAX);
        stray = bound(stray, 0, MAX);
        _stake(alice, staked);
        vm.prank(bob);
        token.transfer(address(sp), stray);

        take = bound(take, 0, staked + stray);
        vm.prank(owner);
        try sp.recover(address(token), take) {
            assertGe(token.balanceOf(address(sp)), sp.totalStakes());
        } catch {
            assertGt(take, stray);
        }
    }
}
