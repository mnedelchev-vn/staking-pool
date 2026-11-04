// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {TestERC20} from "../../contracts/mocks/TestERC20.sol";
import {StakingPool} from "../../contracts/StakingPool.sol";

/// @dev Drives the pool through random, *valid* call sequences and tracks ghost state.
///      Without a handler forge calls the pool from random senders with no approvals,
///      so nearly every call reverts and the invariants are barely exercised.
contract Handler is Test {
    TestERC20 public token;
    StakingPool public sp;
    address public owner;
    address[] public actors;

    uint256 constant MAX_AMOUNT = 1_000_000_000 ether;

    // ghost state
    uint256 public ghostPrevTotalDividends;
    uint256 public ghostPrevRound = 1;
    uint256 public ghostPrevPayoutOfLastRound;
    /// tokens that entered the reward stream (fees + donations)
    uint256 public ghostRewardsIn;
    /// tokens paid out as rewards (claims, stake-time claims, unstake-time claims)
    uint256 public ghostRewardsOut;
    uint256 public calls_stake;
    uint256 public calls_unstake;
    uint256 public calls_claim;
    uint256 public calls_donate;

    constructor(TestERC20 _token, StakingPool _sp, address _owner, address[] memory _actors) {
        token = _token;
        sp = _sp;
        owner = _owner;
        actors = _actors;
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function stake(uint256 actorSeed, uint256 amount) external {
        if (sp.paused()) return;
        address a = _actor(actorSeed);
        amount = bound(amount, 1, MAX_AMOUNT);

        uint256 pending = sp.getPendingReward(a);
        uint256 totalBefore = sp.totalStakes();
        uint256 fee = totalBefore > 0 ? (amount * sp.stakingFee()) / sp.FEE_DENOMINATOR() : 0;

        vm.startPrank(a);
        token.approve(address(sp), amount);
        sp.stake(amount);
        vm.stopPrank();

        ghostRewardsIn += fee;
        ghostRewardsOut += pending;
        calls_stake++;
    }

    function unstake(uint256 actorSeed, uint256 amountSeed) external {
        address a = _actor(actorSeed);
        (uint256 staked,) = sp.stakers(a);
        if (staked == 0) return;
        uint256 amount = bound(amountSeed, 1, staked);

        uint256 pending = sp.getPendingReward(a);
        uint256 totalAfter = sp.totalStakes() - amount;
        uint256 fee = totalAfter > 0 ? (amount * sp.unstakingFee()) / sp.FEE_DENOMINATOR() : 0;

        vm.prank(a);
        sp.unstake(amount);

        ghostRewardsIn += fee;
        ghostRewardsOut += pending;
        calls_unstake++;
    }

    function claim(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        uint256 pending = sp.getPendingReward(a);
        if (pending == 0) return;

        vm.prank(a);
        sp.claimReward();

        ghostRewardsOut += pending;
        calls_claim++;
    }

    function donate(uint256 actorSeed, uint256 amount) external {
        if (sp.paused() || sp.totalStakes() == 0) return;
        address a = _actor(actorSeed);
        amount = bound(amount, 0, MAX_AMOUNT);

        vm.startPrank(a);
        token.approve(address(sp), amount);
        sp.donateToPool(amount);
        vm.stopPrank();

        ghostRewardsIn += amount;
        calls_donate++;
    }

    function setFees(uint16 stakingFee, uint16 unstakingFee) external {
        vm.prank(owner);
        sp.setFees(uint16(bound(stakingFee, 0, 1000)), uint16(bound(unstakingFee, 0, 1000)));
    }

    function setPaused(bool paused) external {
        vm.startPrank(owner);
        if (paused && !sp.paused()) sp.pause();
        if (!paused && sp.paused()) sp.unpause();
        vm.stopPrank();
    }

    /// @dev called by the invariant suite after each call to check monotonic counters
    function snapshot() external {
        ghostPrevTotalDividends = sp.totalDividends();
        ghostPrevRound = sp.round();
        ghostPrevPayoutOfLastRound = sp.payouts(sp.round() - 1);
    }
}
