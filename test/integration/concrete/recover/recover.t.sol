// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TestERC20} from "../../../../contracts/mocks/TestERC20.sol";
import {StakingPool} from "../../../../contracts/StakingPool.sol";
import {Modifiers} from "../../../utils/Modifiers.sol";

contract Recover_Integration_Concrete_Test is Modifiers {
    uint256 internal constant STRAY = 100e18;

    function test_RevertWhen_CallerNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        sp.recover(address(token), 1);
    }

    function test_RevertGiven_PoolEthBalanceInsufficient() external whenCallerOwner whenTokenIsNative {
        deal(address(sp), 1 ether);

        // A failed ETH call surfaces as InvalidRecover, not as a silent no-op.
        vm.expectRevert(StakingPool.InvalidRecover.selector);
        vm.prank(owner);
        sp.recover(address(0), 1 ether + 1);
    }

    function test_GivenPoolEthBalanceSufficient() external whenCallerOwner whenTokenIsNative {
        deal(address(sp), 1 ether);
        uint256 ownerBalanceBefore = owner.balance;

        // It should emit {Recovered} event.
        vm.expectEmit(address(sp));
        emit StakingPool.Recovered(address(0), 1 ether);

        vm.prank(owner);
        sp.recover(address(0), 1 ether);

        // It should send the ETH to the owner.
        assertEq(owner.balance, ownerBalanceBefore + 1 ether, "owner ETH");
        // It should reduce the pool ETH balance.
        assertEq(address(sp).balance, 0, "pool ETH");
    }

    function test_RevertWhen_TokenNotAContract() external whenCallerOwner whenTokenIsAnERC20 {
        address eoa = makeAddr("eoa");

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, eoa));
        vm.prank(owner);
        sp.recover(eoa, 1);
    }

    function test_RevertGiven_RecoveryLeavesPoolBelowTotalStakes()
        external
        whenCallerOwner
        whenTokenIsAnERC20
        whenTokenIsTheStakingToken
    {
        _stake(alice, FIRST_STAKE);
        vm.prank(bob);
        token.transfer(address(sp), STRAY);

        // One wei of staker principal would be taken.
        vm.expectRevert(StakingPool.InvalidRecover.selector);
        vm.prank(owner);
        sp.recover(address(token), STRAY + 1);
    }

    function test_GivenRecoveryLeavesPoolAtTotalStakes()
        external
        whenCallerOwner
        whenTokenIsAnERC20
        whenTokenIsTheStakingToken
    {
        _stake(alice, FIRST_STAKE);
        vm.prank(bob);
        token.transfer(address(sp), STRAY);
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        // It should emit {Recovered} event.
        vm.expectEmit(address(sp));
        emit StakingPool.Recovered(address(token), STRAY);

        vm.prank(owner);
        sp.recover(address(token), STRAY);

        // It should send the surplus to the owner. The boundary (balance == totalStakes) is allowed.
        assertEq(token.balanceOf(owner), ownerBalanceBefore + STRAY, "owner balance");
        assertEq(token.balanceOf(address(sp)), sp.totalStakes(), "pool == totalStakes");
        assertEq(_stakedOf(alice), FIRST_STAKE, "alice stake untouched");
    }

    /// @dev KNOWN LIMITATION (characterization test, documents current behavior).
    /// recover() only protects `totalStakes`. Unclaimed rewards are held in the same token balance above
    /// `totalStakes`, so the owner can recover them and leave stakers with unbacked reward claims.
    /// If recover() is hardened, flip this test to expect `InvalidRecover`.
    function test_GivenPoolSurplusIncludesUnclaimedRewards()
        external
        whenCallerOwner
        whenTokenIsAnERC20
        whenTokenIsTheStakingToken
    {
        _stakeAliceThenBob();
        // The whole surplus above the principal is the 1_000 entry fee, owed to alice (20) and bob (980).
        uint256 owed = POOL_BALANCE_AFTER_SECOND - TOTAL_STAKES_AFTER_SECOND;
        assertEq(owed, SECOND_STAKE_FEE, "test premise");

        // It should let the owner recover the rewards.
        vm.prank(owner);
        sp.recover(address(token), owed);
        assertEq(token.balanceOf(address(sp)), sp.totalStakes(), "pool holds principal only");

        // Harm: the pool is now insolvent for rewards. alice can still leave (she is paid out of bob's principal)...
        _unstake(alice, FIRST_STAKE);
        // ...but the last staker can no longer exit in full.
        uint256 bobStake = _stakedOf(bob);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        vm.prank(bob);
        sp.unstake(bobStake);
    }

    function test_WhenTokenIsAnotherERC20() external whenCallerOwner whenTokenIsAnERC20 {
        TestERC20 other = new TestERC20();
        other.mint(alice, 500e18);
        vm.prank(alice);
        other.transfer(address(sp), 500e18); // sent by mistake
        _stakeAliceThenBob();

        uint256 poolStakingBalanceBefore = token.balanceOf(address(sp));
        uint256 totalStakesBefore = sp.totalStakes();
        uint256 totalDividendsBefore = sp.totalDividends();
        uint256 roundBefore = sp.round();
        uint256 ownerBalanceBefore = other.balanceOf(owner);

        // It should emit {Recovered} event.
        vm.expectEmit(address(sp));
        emit StakingPool.Recovered(address(other), 500e18);

        vm.prank(owner);
        sp.recover(address(other), 500e18);

        // It should send the tokens to the owner.
        assertEq(other.balanceOf(owner), ownerBalanceBefore + 500e18, "owner balance");
        assertEq(other.balanceOf(address(sp)), 0, "pool balance of the other token");
        // It should leave the staking accounting untouched.
        assertEq(token.balanceOf(address(sp)), poolStakingBalanceBefore, "staking token balance");
        assertEq(sp.totalStakes(), totalStakesBefore, "totalStakes");
        assertEq(sp.totalDividends(), totalDividendsBefore, "totalDividends");
        assertEq(sp.round(), roundBefore, "round");
    }
}
