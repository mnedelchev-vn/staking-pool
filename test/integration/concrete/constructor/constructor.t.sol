// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Base_Test} from "../../../utils/Base.t.sol";
import {StakingPool} from "../../../../contracts/StakingPool.sol";

contract Constructor_Integration_Concrete_Test is Base_Test {
    function test_RevertWhen_StakingFeeExceedsMax() external {
        vm.expectRevert(StakingPool.InvalidFees.selector);
        new StakingPool(address(token), MAX_FEE + 1, UNSTAKING_FEE);
    }

    function test_RevertWhen_UnstakingFeeExceedsMax() external {
        vm.expectRevert(StakingPool.InvalidFees.selector);
        new StakingPool(address(token), STAKING_FEE, MAX_FEE + 1);
    }

    function test_WhenFeesWithinMax() external {
        // Distinct values so a swapped assignment is caught.
        vm.prank(owner);
        StakingPool pool = new StakingPool(address(token), 123, 456);

        // It should set the staking token.
        assertEq(address(pool.token()), address(token), "token");
        // It should set the deployer as the owner.
        assertEq(pool.owner(), owner, "owner");
        // It should set both fees.
        assertEq(pool.stakingFee(), 123, "stakingFee");
        assertEq(pool.unstakingFee(), 456, "unstakingFee");
        // It should start unpaused at round one with empty accounting.
        assertFalse(pool.paused(), "paused");
        assertEq(pool.round(), 1, "round");
        assertEq(pool.totalStakes(), 0, "totalStakes");
        assertEq(pool.totalDividends(), 0, "totalDividends");
        assertEq(pool.scaledRemainder(), 0, "scaledRemainder");
        assertEq(pool.SCALING(), SCALING, "SCALING");
        assertEq(pool.FEE_DENOMINATOR(), FEE_DENOMINATOR, "FEE_DENOMINATOR");
    }
}
