// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {TestERC20} from "../contracts/TestERC20.sol";
import {StakingPool} from "../contracts/StakingPool.sol";


contract TestStakingPool is Test {
    TestERC20 public token;
    StakingPool public sp;
    uint256 constant public MAX_UINT = 2 ** 256 - 1;
    uint256 constant public USER_TOKEN_BALANCE = 1000 * 10 ** 18;
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");

    function setUp() public {
        token = new TestERC20();
        token.mint(address(this), MAX_UINT);

        sp = new StakingPool(address(token), 2, 2);

        // setup test users with assets
        deal(user1, 1000 ether);
        deal(user2, 1000 ether);
        deal(address(token), user1, USER_TOKEN_BALANCE);
        deal(address(token), user2, USER_TOKEN_BALANCE);
    }

    function _stake(uint value, address msgSender) internal {
        vm.assume(value > 0);

        uint spBalance = token.balanceOf(address(sp));
        uint testBalance = token.balanceOf(msgSender);
        uint pendingReward = sp.getPendingReward(msgSender);
        (uint256 stakedTokensBefore,) = sp.stakers(msgSender);

        token.approve(address(sp), value);
        sp.stake(value);

        (uint256 stakedTokensAfter,) = sp.stakers(msgSender);

        require(stakedTokensAfter != 0 && stakedTokensAfter > stakedTokensBefore, 'ERROR: invalid stakers mapping value after stake');
        require(spBalance - pendingReward < token.balanceOf(address(sp)), 'ERROR: invalid pool balance after stake');
        require(testBalance > token.balanceOf(msgSender) - pendingReward, 'ERROR: invalid test contract balance after stake');
    }

    function _unstake(address msgSender) internal {
        (uint256 stakedTokens,) = sp.stakers(msgSender);
        uint spBalance = token.balanceOf(address(sp));
        uint testBalance = token.balanceOf(msgSender);
        sp.unstake(stakedTokens);

        (uint256 stakedTokensAfter,) = sp.stakers(msgSender);

        require(stakedTokensAfter == 0);
        require(spBalance > token.balanceOf(address(sp)), 'ERROR: invalid pool balance after unstake');
        require(testBalance < token.balanceOf(msgSender), 'ERROR: invalid test contract balance after unstake');
    }

    function _claim(address msgSender) internal {
        uint pendingReward = sp.getPendingReward(msgSender);
        uint spBalance = token.balanceOf(address(sp));
        (uint256 stakedTokensBefore,) = sp.stakers(msgSender);

        sp.claimReward();

        (uint256 stakedTokensAfter,) = sp.stakers(msgSender);

        require(sp.getPendingReward(msgSender) == 0 && pendingReward > sp.getPendingReward(msgSender));
        // verify only the reward amount is being withdrawn out of the pool
        require(spBalance == token.balanceOf(address(sp)) + pendingReward, 'ERROR: invalid test contract balance after claiming');
        // verify that shares stay the same for the claimer
        require(stakedTokensBefore == stakedTokensAfter, 'ERROR: invalid stakers mapping value after claim');
    }

    function testStake(uint value) public {
        _stake(value, address(this));
    }

    function testUnstake(uint value) public {
        _stake(value, address(this));
        _unstake(address(this));
    }

    function testDonate(uint64 value) public {
        vm.assume(value > 0);

        _stake(10 * 10 ** 18, address(this));

        vm.startPrank(user1);
        uint spBalance = token.balanceOf(address(sp));
        uint testBalance = token.balanceOf(user1);
        (uint256 stakedTokensBefore,) = sp.stakers(user1);

        token.approve(address(sp), value);
        sp.donateToPool(value);

        (uint256 stakedTokensAfter,) = sp.stakers(user1);

        require(spBalance + value == token.balanceOf(address(sp)), 'ERROR: invalid pool balance after donate');
        require(testBalance == token.balanceOf(user1) + value, 'ERROR: invalid test contract balance after donate');
        // verify that no shares have been minted for the donator
        require(stakedTokensBefore == stakedTokensAfter, 'ERROR: invalid stakers mapping value after donate');
    }

    function testTwoUsersStakingAndUnstaking(uint64[3] calldata value1, uint64[3] calldata value2) public {
        // both users staking one after another
        vm.startPrank(user1);
        _stake(value1[0], user1);

        vm.startPrank(user2);
        _stake(value2[0], user2);

        vm.startPrank(user1);
        _stake(value1[1], user1);

        vm.startPrank(user2);
        _stake(value2[1], user2);

        vm.startPrank(user1);
        _stake(value1[2], user1);

        vm.startPrank(user2);
        _stake(value2[2], user2);

        // both users unstaking
        vm.startPrank(user1);
        _unstake(user1);

        vm.startPrank(user2);
        _unstake(user2);
    }

    function testClaimingRewards(uint256 value1, uint256 value2) public {
        // both values should be between 1 * 10 ** 18 and max uint64
        value1 = bound(value1, 1 ether, 2 ** 64 - 1);
        value2 = bound(value2, 1 ether, 2 ** 64 - 1);

        // both users staking
        vm.startPrank(user1);
        _stake(value1, user1);

        // verify user1 has no rewards yet, because he is the only staker inside the pool
        require(sp.getPendingReward(user1) == 0, 'ERROR: invalid rewards on first stake');

        vm.startPrank(user2);
        _stake(value2, user2);

        // verify both users have rewards, because user2 has staked also and both users own pool shares
        require(sp.getPendingReward(user1) != 0 && sp.getPendingReward(user2) != 0, 'ERROR: invalid rewards on second stake');

        // claim rewards from both users
        vm.startPrank(user1);
        _claim(user1);

        vm.startPrank(user2);
        _claim(user2);
    }
}