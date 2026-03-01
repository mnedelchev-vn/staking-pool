// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {TestERC20} from "../contracts/mocks/TestERC20.sol";
import {StakingPool} from "../contracts/StakingPool.sol";


contract TestStakingPool is Test {
    TestERC20 public token;
    StakingPool public sp;
    uint256 constant public USER_TOKEN_BALANCE = 100000000000 ether;
    address internal owner = makeAddr("owner");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");

    function setUp() public {
        deal(owner, 1000 ether);
        deal(user1, 1000 ether);
        deal(user2, 1000 ether);

        vm.startPrank(owner);

        token = new TestERC20();
        token.mint(owner, 1000 ether);
        token.mint(user1, USER_TOKEN_BALANCE);
        token.mint(user2, USER_TOKEN_BALANCE);
        sp = new StakingPool(address(token), 200, 200);
        
        vm.stopPrank();
    }

    /**
    ************************ FUZZING ************************
    */

    function _stake(uint value, address msgSender) internal {
        vm.assume(value > 0);

        uint spBalance = token.balanceOf(address(sp));
        uint testBalance = token.balanceOf(msgSender);
        uint pendingReward = sp.getPendingReward(msgSender);
        (uint256 stakedTokensBefore,) = sp.stakers(msgSender);

        token.approve(address(sp), value);
        sp.stake(value);

        (uint256 stakedTokensAfter,) = sp.stakers(msgSender);

        assert(stakedTokensAfter != 0 && stakedTokensAfter > stakedTokensBefore);
        assert(spBalance - pendingReward < token.balanceOf(address(sp)));
        assert(testBalance > token.balanceOf(msgSender) - pendingReward);
    }

    function _unstake(address msgSender) internal {
        (uint256 stakedTokens,) = sp.stakers(msgSender);
        uint spBalance = token.balanceOf(address(sp));
        uint testBalance = token.balanceOf(msgSender);
        sp.unstake(stakedTokens);

        (uint256 stakedTokensAfter,) = sp.stakers(msgSender);

        assert(stakedTokensAfter == 0);
        assert(spBalance > token.balanceOf(address(sp)));
        assert(testBalance < token.balanceOf(msgSender));
    }

    function _claim(address msgSender) internal {
        uint pendingReward = sp.getPendingReward(msgSender);
        uint spBalance = token.balanceOf(address(sp));
        (uint256 stakedTokensBefore,) = sp.stakers(msgSender);

        sp.claimReward();

        (uint256 stakedTokensAfter,) = sp.stakers(msgSender);

        assert(sp.getPendingReward(msgSender) == 0 && pendingReward > sp.getPendingReward(msgSender));
        // verify only the reward amount is being withdrawn out of the pool
        assert(spBalance == token.balanceOf(address(sp)) + pendingReward);
        // verify that shares stay the same for the claimer
        assert(stakedTokensBefore == stakedTokensAfter);
    }

    function testStake(uint value) public {
        value = bound(value, 0, USER_TOKEN_BALANCE);

        vm.startPrank(user1);
        _stake(value, user1);
        vm.stopPrank();
    }

    function testUnstake(uint value) public {
        value = bound(value, 0, USER_TOKEN_BALANCE);

        vm.startPrank(user1);
        _stake(value, user1);
        _unstake(user1);
        vm.stopPrank();
    }

    function testDonate(uint value) public {
        value = bound(value, 0, USER_TOKEN_BALANCE);

        vm.startPrank(user1);
        _stake(value, user1);

        uint spInitialBalance = token.balanceOf(address(sp));
        uint user1InitialBalance = token.balanceOf(user1);
        (uint256 stakedTokensBefore,) = sp.stakers(user1);

        vm.startPrank(owner);
        uint donationAmount = 1000 * 10 ** 18;
        token.approve(address(sp), donationAmount);
        sp.donateToPool(donationAmount);

        (uint256 stakedTokensAfter,) = sp.stakers(user1);

        assert(spInitialBalance + donationAmount == token.balanceOf(address(sp)));
        assert(user1InitialBalance == token.balanceOf(user1));
        // verify that no shares have been minted for the donator
        assert(stakedTokensBefore == stakedTokensAfter);
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
        // both values should be between 1 ether and USER_TOKEN_BALANCE
        value1 = bound(value1, 1 ether, USER_TOKEN_BALANCE);
        value2 = bound(value2, 1 ether, USER_TOKEN_BALANCE);

        // both users staking
        vm.startPrank(user1);
        _stake(value1, user1);

        // verify user1 has no rewards yet, because he is the only staker inside the pool
        assert(sp.getPendingReward(user1) == 0);

        vm.startPrank(user2);
        _stake(value2, user2);

        // verify both users have rewards, because user2 has staked also and both users own pool shares
        assert(sp.getPendingReward(user1) != 0 && sp.getPendingReward(user2) != 0);

        // claim rewards from both users
        vm.startPrank(user1);
        _claim(user1);

        vm.startPrank(user2);
        _claim(user2);
    }

    function test_pause() public {
        vm.startPrank(owner);
        sp.pause();
        assert(sp.paused() == true);
        vm.stopPrank();
    }

    function test_unpause() public {
        vm.startPrank(owner);
        sp.pause();
        sp.unpause();
        assert(sp.paused() == false);
        vm.stopPrank();
    }

    function test_setFees(uint16 _stakingFee, uint16 _unstakingFee) public {
        vm.startPrank(owner);
        uint16 stakingFee = uint16(bound(_stakingFee, 0, 1000));
        uint16 unstakingFee = uint16(bound(_unstakingFee, 0, 1000));
        sp.setFees(stakingFee, unstakingFee);
        assert(sp.stakingFee() == stakingFee && sp.unstakingFee() == unstakingFee);
        vm.stopPrank();
    }

    function test_recoverStakingToken(uint256 amount) public {
        vm.startPrank(user1);
        amount = bound(amount, 1, USER_TOKEN_BALANCE);
        token.transfer(address(sp), amount); /// mistakenly sent assets to the pool

        uint initialOwnerBalance = token.balanceOf(owner);
        uint initialPoolBalance = token.balanceOf(address(sp));

        vm.startPrank(owner);
        sp.recover(address(token), amount);

        assert(token.balanceOf(owner) == initialOwnerBalance + amount);
        assert(initialPoolBalance - amount == token.balanceOf(address(sp)));

        vm.stopPrank();
    }

    function test_recoverArbitraryToken(uint256 amount) public {
        TestERC20 arbitraryToken = new TestERC20();
        arbitraryToken.mint(user1, USER_TOKEN_BALANCE);

        vm.startPrank(user1);
        amount = bound(amount, 1, USER_TOKEN_BALANCE);
        arbitraryToken.transfer(address(sp), amount); /// mistakenly sent assets to the pool

        uint initialOwnerBalance = arbitraryToken.balanceOf(owner);
        uint initialPoolBalance = arbitraryToken.balanceOf(address(sp));

        vm.startPrank(owner);
        sp.recover(address(arbitraryToken), amount);

        assert(arbitraryToken.balanceOf(owner) == initialOwnerBalance + amount);
        assert(initialPoolBalance - amount == arbitraryToken.balanceOf(address(sp)));

        vm.stopPrank();
    }

    function test_recoverETH(uint256 amount) public {
        amount = bound(amount, 1, USER_TOKEN_BALANCE);
        deal(address(sp), amount); /// mistakenly sent ether to the pool

        uint initialOwnerBalance = owner.balance;
        uint initialPoolBalance = address(sp).balance;

        vm.startPrank(owner);
        sp.recover(address(0), amount);

        assert(owner.balance == initialOwnerBalance + amount);
        assert(initialPoolBalance - amount == address(sp).balance);

        vm.stopPrank();
    }

    /**
    ************************ INVARIANTS ************************
    */

    function invariant_fees() public view {
        assert(sp.stakingFee() <= 1000 && sp.unstakingFee() <= 1000);
    }

    function invariant_totalStakes() public view {
        assert(token.balanceOf(address(sp)) == sp.totalStakes());
    }

    function invariant_lastPayoutAlwaysPositive() public view {
        if (sp.round() > 1) { /// round 1 could be empty if not stakes yet
            assert(sp.payouts(sp.round() - 1) > 0);
        }
    }

    function invariant_alwaysWithdrawableUnlessPaused() public {
        if (!sp.paused()) {
            vm.startPrank(user1);
            _stake(1 ether, user1);
            _unstake(user1);
            vm.stopPrank();
        }
    }

    /// invariant donate to pool always possible

    /// invariant claimReward always possible if pending rewards > 0
}