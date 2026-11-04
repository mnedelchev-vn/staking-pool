// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TestERC20} from "../contracts/mocks/TestERC20.sol";
import {StakingPool} from "../contracts/StakingPool.sol";
import {Handler} from "./handlers/StakingPoolHandler.sol";

contract StakingPoolInvariants is StdInvariant, Test {
    TestERC20 token;
    StakingPool sp;
    Handler handler;
    address owner = makeAddr("owner");
    address[] actors;

    uint256 constant ACTOR_BALANCE = 1_000_000_000_000 ether;

    function setUp() public {
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));

        vm.startPrank(owner);
        token = new TestERC20();
        sp = new StakingPool(address(token), 200, 200);
        for (uint256 i; i < actors.length; i++) {
            token.mint(actors[i], ACTOR_BALANCE);
        }
        vm.stopPrank();

        handler = new Handler(token, sp, owner, actors);

        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = Handler.stake.selector;
        selectors[1] = Handler.unstake.selector;
        selectors[2] = Handler.claim.selector;
        selectors[3] = Handler.donate.selector;
        selectors[4] = Handler.setFees.selector;
        selectors[5] = Handler.setPaused.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function _sumStaked() internal view returns (uint256 sum) {
        for (uint256 i; i < actors.length; i++) {
            (uint256 s,) = sp.stakers(actors[i]);
            sum += s;
        }
    }

    function _sumPending() internal view returns (uint256 sum) {
        for (uint256 i; i < actors.length; i++) {
            sum += sp.getPendingReward(actors[i]);
        }
    }

    /// Accounting: totalStakes is exactly the sum of every staker's balance.
    function invariant_totalStakesEqualsSumOfStakes() public view {
        assertEq(sp.totalStakes(), _sumStaked());
    }

    /// Solvency: the pool can pay every staker's principal AND every pending reward at once.
    function invariant_solvency() public view {
        assertGe(token.balanceOf(address(sp)), sp.totalStakes() + _sumPending());
    }

    /// Conservation: the pool holds exactly principal + unclaimed rewards + rounding dust.
    /// Dust is the not-yet-distributed fractional part, so it is bounded by the
    /// number of payout rounds (each can strand < 1 token per staker-share).
    function invariant_balanceDecomposition() public view {
        uint256 bal = token.balanceOf(address(sp));
        uint256 accounted = sp.totalStakes() + _sumPending();
        // every token that entered the reward stream is either paid out, pending, or dust
        assertEq(
            handler.ghostRewardsIn() - handler.ghostRewardsOut(),
            bal - sp.totalStakes() - 0, // rewards still held by the pool
            "reward ledger drift"
        );
        assertGe(bal, accounted);
    }

    /// Nobody can ever receive more reward tokens than were put into the reward stream.
    function invariant_rewardsOutNeverExceedRewardsIn() public view {
        assertLe(handler.ghostRewardsOut(), handler.ghostRewardsIn());
    }

    /// Reward index is monotonic and in lock-step with `round`.
    function invariant_payoutsMonotonic() public {
        assertGe(sp.totalDividends(), handler.ghostPrevTotalDividends());
        assertGe(sp.round(), handler.ghostPrevRound());
        assertGe(sp.payouts(sp.round() - 1), handler.ghostPrevPayoutOfLastRound());
        // the cumulative index of the latest round is the global dividends counter
        assertEq(sp.payouts(sp.round() - 1), sp.totalDividends());
        handler.snapshot();
    }

    /// Rounding dust: tokens held beyond principal + pending rewards are the not-yet-distributed
    /// remainder plus per-payout flooring. The pool must never hold *less* (solvency) and the
    /// surplus must stay tiny relative to the volume that went through the reward stream.
    function invariant_dustIsNegligible() public view {
        uint256 surplus = token.balanceOf(address(sp)) - sp.totalStakes() - _sumPending();
        uint256 rewardsIn = handler.ghostRewardsIn();
        // allow up to 1 wei per payout round per actor, plus the carried remainder
        uint256 allowed = sp.round() * actors.length + sp.scaledRemainder() / sp.SCALING() + 1;
        assertLe(surplus, allowed + rewardsIn / 1e6);
    }

    /// Fees stay within the setFees cap no matter what sequence ran.
    function invariant_feesWithinCap() public view {
        assertLe(sp.stakingFee(), sp.FEE_DENOMINATOR() / 10);
        assertLe(sp.unstakingFee(), sp.FEE_DENOMINATOR() / 10);
    }

    /// Liveness: every staker can always exit in full (pool is not locked by any sequence).
    function invariant_everyStakerCanFullyExit() public {
        uint256 snap = vm.snapshotState();
        for (uint256 i; i < actors.length; i++) {
            (uint256 s,) = sp.stakers(actors[i]);
            if (s == 0) continue;
            vm.prank(actors[i]);
            sp.unstake(s); // must not revert
        }
        assertEq(sp.totalStakes(), 0);
        vm.revertToState(snap);
    }

    function afterInvariant() public view {
        console2.log("stake/unstake/claim/donate");
        console2.log(handler.calls_stake(), handler.calls_unstake());
        console2.log(handler.calls_claim(), handler.calls_donate());
    }
}
