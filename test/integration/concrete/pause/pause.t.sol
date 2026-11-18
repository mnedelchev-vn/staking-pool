// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Modifiers} from "../../../utils/Modifiers.sol";

contract Pause_Integration_Concrete_Test is Modifiers {
    function test_RevertWhen_CallerNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        sp.pause();
    }

    function test_RevertGiven_Paused() external whenCallerOwner {
        _pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(owner);
        sp.pause();
    }

    function test_GivenNotPaused() external whenCallerOwner {
        // It should emit {Paused} event.
        vm.expectEmit(address(sp));
        emit Pausable.Paused(owner);

        vm.prank(owner);
        sp.pause();

        // It should pause the pool.
        assertTrue(sp.paused(), "paused");
    }
}
