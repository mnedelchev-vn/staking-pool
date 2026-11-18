// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StakingPool} from "../../../../contracts/StakingPool.sol";
import {Modifiers} from "../../../utils/Modifiers.sol";

contract SetFees_Integration_Concrete_Test is Modifiers {
    function test_RevertWhen_CallerNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        sp.setFees(STAKING_FEE, UNSTAKING_FEE);
    }

    function test_RevertWhen_StakingFeeExceedsMax() external whenCallerOwner {
        // One basis point over the 10% cap, while the other fee is valid.
        vm.expectRevert(StakingPool.InvalidFees.selector);
        vm.prank(owner);
        sp.setFees(MAX_FEE + 1, UNSTAKING_FEE);
    }

    function test_RevertWhen_UnstakingFeeExceedsMax() external whenCallerOwner {
        vm.expectRevert(StakingPool.InvalidFees.selector);
        vm.prank(owner);
        sp.setFees(STAKING_FEE, MAX_FEE + 1);
    }

    function test_WhenFeesZero() external whenCallerOwner {
        vm.prank(owner);
        sp.setFees(0, 0);

        // It should set both fees to zero.
        assertEq(sp.stakingFee(), 0, "stakingFee");
        assertEq(sp.unstakingFee(), 0, "unstakingFee");
    }

    function test_WhenFeesAtMax() external whenCallerOwner {
        vm.prank(owner);
        sp.setFees(MAX_FEE, MAX_FEE);

        // It should set both fees to the max.
        assertEq(sp.stakingFee(), MAX_FEE, "stakingFee");
        assertEq(sp.unstakingFee(), MAX_FEE, "unstakingFee");
    }

    function test_WhenFeesDiffer() external whenCallerOwner {
        vm.prank(owner);
        sp.setFees(111, 222);

        // It should set each fee independently.
        assertEq(sp.stakingFee(), 111, "stakingFee");
        assertEq(sp.unstakingFee(), 222, "unstakingFee");
    }
}
