// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Modifiers} from "../../../utils/Modifiers.sol";

contract Unpause_Integration_Concrete_Test is Modifiers {
    function test_RevertWhen_CallerNotOwner() external {
        _pause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        sp.unpause();
    }

    function test_RevertGiven_NotPaused() external whenCallerOwner {
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vm.prank(owner);
        sp.unpause();
    }

    function test_GivenPaused() external whenCallerOwner givenPaused {
        // It should emit {Unpaused} event.
        vm.expectEmit(address(sp));
        emit Pausable.Unpaused(owner);

        vm.prank(owner);
        sp.unpause();

        // It should unpause the pool.
        assertFalse(sp.paused(), "paused");

        // It should reopen staking.
        _stake(alice, FIRST_STAKE);
        assertEq(_stakedOf(alice), FIRST_STAKE, "staked after unpause");
    }
}
