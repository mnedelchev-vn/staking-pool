// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Base_Test} from "./Base.t.sol";

/// @notice BTT path modifiers shared by every concrete test.
/// @dev Modifiers that only document the path are empty on purpose. A test never carries a modifier named after its
/// own innermost condition: that condition is set up in the test body.
abstract contract Modifiers is Base_Test {
    /*//////////////////////////////////////////////////////////////////////////
                              PATH-DOCUMENTING (EMPTY)
    //////////////////////////////////////////////////////////////////////////*/

    modifier givenNotPaused() {
        _;
    }

    modifier whenCallerOwner() {
        _;
    }

    modifier whenAmountNotZero() {
        _;
    }

    modifier whenAmountWithinStakedBalance() {
        _;
    }

    modifier givenSufficientAllowanceAndBalance() {
        _;
    }

    modifier givenNoPendingReward() {
        _;
    }

    modifier whenTokenIsAnERC20() {
        _;
    }

    modifier whenTokenIsTheStakingToken() {
        _;
    }

    modifier whenTokenIsNative() {
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   STATE SET-UP
    //////////////////////////////////////////////////////////////////////////*/

    modifier givenPaused() {
        _pause();
        _;
    }

    /// @dev alice is the only staker (no fee was charged, no payout round opened).
    modifier givenStakesInPool() {
        _stake(alice, FIRST_STAKE);
        _;
    }

    /// @dev alice and bob are staked, see the scenario in Base_Test.
    modifier givenTwoStakers() {
        _stakeAliceThenBob();
        _;
    }

    modifier givenPendingReward() {
        _stakeAliceThenBob();
        _;
    }

    modifier givenOtherStakersRemain() {
        _stakeAliceThenBob();
        _;
    }
}
