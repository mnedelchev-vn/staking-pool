// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TestERC20} from "../../contracts/mocks/TestERC20.sol";
import {StakingPool} from "../../contracts/StakingPool.sol";

/// @notice Shared deployment, constants and helpers for the BTT-style integration tests.
/// @dev The staking and unstaking fees are deliberately DIFFERENT (2% / 3%) so a swapped-fee bug cannot hide.
///
/// Scenario numbers are chosen so the reward math divides exactly (no rounding noise in assertions):
///
///   alice stakes FIRST_STAKE (pool empty -> no fee)            totalStakes = 1_000
///   bob stakes SECOND_STAKE gross (2% fee = 1_000, net 49_000) totalStakes = 50_000
///   dividendPerToken = 1_000e18 * 1e18 / 50_000e18            = 2e16 exactly, scaledRemainder = 0
///   => alice pending = 20e18, bob pending = 980e18, pool balance = 51_000e18, round = 2
abstract contract Base_Test is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    uint16 internal constant STAKING_FEE = 200; // 2%
    uint16 internal constant UNSTAKING_FEE = 300; // 3%
    uint16 internal constant MAX_FEE = 1_000; // 10%, the cap enforced by setFees
    uint256 internal constant FEE_DENOMINATOR = 10_000;
    uint256 internal constant SCALING = 1e18;
    uint256 internal constant USER_BALANCE = 1_000_000_000_000e18;

    uint256 internal constant FIRST_STAKE = 1_000e18;
    uint256 internal constant SECOND_STAKE = 50_000e18;
    uint256 internal constant SECOND_STAKE_FEE = 1_000e18;
    uint256 internal constant SECOND_STAKE_NET = 49_000e18;
    uint256 internal constant TOTAL_STAKES_AFTER_SECOND = 50_000e18;
    uint256 internal constant DIVIDEND_PER_TOKEN_AFTER_SECOND = 2e16;
    uint256 internal constant ALICE_PENDING_AFTER_SECOND = 20e18;
    uint256 internal constant BOB_PENDING_AFTER_SECOND = 980e18;
    uint256 internal constant POOL_BALANCE_AFTER_SECOND = 51_000e18;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    TestERC20 internal token;
    StakingPool internal sp;

    /*//////////////////////////////////////////////////////////////////////////
                                      ACCOUNTS
    //////////////////////////////////////////////////////////////////////////*/

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    /// @dev Never receives tokens.
    address internal dave = makeAddr("dave");

    /*//////////////////////////////////////////////////////////////////////////
                                       SET-UP
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        vm.startPrank(owner);
        token = new TestERC20();
        sp = new StakingPool(address(token), STAKING_FEE, UNSTAKING_FEE);
        token.mint(alice, USER_BALANCE);
        token.mint(bob, USER_BALANCE);
        token.mint(carol, USER_BALANCE);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _approve(address user, uint256 amount) internal {
        vm.prank(user);
        token.approve(address(sp), amount);
    }

    function _stake(address user, uint256 amount) internal {
        _approve(user, amount);
        vm.prank(user);
        sp.stake(amount);
    }

    function _unstake(address user, uint256 amount) internal {
        vm.prank(user);
        sp.unstake(amount);
    }

    function _claim(address user) internal {
        vm.prank(user);
        sp.claimReward();
    }

    function _donate(address user, uint256 amount) internal {
        _approve(user, amount);
        vm.prank(user);
        sp.donateToPool(amount);
    }

    function _pause() internal {
        vm.prank(owner);
        sp.pause();
    }

    /// @dev alice stakes first (no fee), then bob stakes: see the scenario numbers in the contract NatSpec.
    function _stakeAliceThenBob() internal {
        _stake(alice, FIRST_STAKE);
        _stake(bob, SECOND_STAKE);
    }

    function _stakedOf(address user) internal view returns (uint256 staked) {
        (staked,) = sp.stakers(user);
    }

    function _roundOf(address user) internal view returns (uint256 round_) {
        (, round_) = sp.stakers(user);
    }

    function _fee(uint256 amount, uint16 feeBps) internal pure returns (uint256) {
        return (amount * feeBps) / FEE_DENOMINATOR;
    }
}
