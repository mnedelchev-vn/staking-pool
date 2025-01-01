const { ethers } = require("hardhat");
const { expect } = require("chai");

describe('Strategy test init.', async function () {
    let TestERC20;
    let StakingPoolContract;
    let owner, user1, user2, user3;

    before(async function() {
        [owner, user1, user2, user3] = await ethers.getSigners();
        console.log(owner, 'owner');

        // deploy dummy token
        TestERC20 = await ethers.deployContract("TestERC20");
        await TestERC20.waitForDeployment();
        expect(await TestERC20.owner()).to.eq(owner.address);
        console.log('TestERC20 deployed at address: ', TestERC20.target);

        let balanceOfOwner = await TestERC20.balanceOf(owner.address);
        let tx = await TestERC20.mint(owner.address, ethers.parseUnits('10000000', 18));
        await tx.wait(1);
        expect(await TestERC20.balanceOf(owner.address)).to.greaterThan(balanceOfOwner);

        // grant user1, user2 and user3 with dummy tokens
        await TestERC20.connect(owner).transfer(user1.address, ethers.parseUnits('1000', 18));
        await TestERC20.connect(owner).transfer(user2.address, ethers.parseUnits('1000', 18));
        await TestERC20.connect(owner).transfer(user3.address, ethers.parseUnits('1000', 18));
        expect(await TestERC20.balanceOf(user1.address)).to.be.greaterThan(0);
        expect(await TestERC20.balanceOf(user2.address)).to.be.greaterThan(0);
        expect(await TestERC20.balanceOf(user3.address)).to.be.greaterThan(0);

        // deploy staking pool
        StakingPoolContract = await ethers.deployContract("StakingPool", [
            TestERC20.target, 
            2, 
            2
        ]);
        await StakingPoolContract.waitForDeployment();
        console.log('StakingPool deployed at address: ', StakingPoolContract.target);
        expect(await StakingPoolContract.owner()).to.eq(owner.address);
    });

    it('Test stake with user1', async function () {
        const initialBalance = await TestERC20.balanceOf(user1.address);
        const stakerAtStart = await StakingPoolContract.stakers(user1.address);
        const amount = ethers.parseUnits('500', 18);
        await TestERC20.connect(user1).approve(StakingPoolContract.target, amount);
        await StakingPoolContract.connect(user1).stake(amount);

        const stakerAtEnd = await StakingPoolContract.stakers(user1.address);
        expect(stakerAtEnd.stakedTokens).to.be.greaterThan(stakerAtStart.stakedTokens);
        expect(initialBalance).to.be.greaterThan(await TestERC20.balanceOf(user1.address));
    });

    it('Test stake with user2', async function () {
        const initialBalance = await TestERC20.balanceOf(user2.address);
        const stakerAtStart = await StakingPoolContract.stakers(user2.address);
        const user1PendingRewards = await StakingPoolContract.getPendingReward(user1.address);
        const user2PendingRewards = await StakingPoolContract.getPendingReward(user2.address);
        const amount = ethers.parseUnits('750', 18);
        await TestERC20.connect(user2).approve(StakingPoolContract.target, amount);
        await StakingPoolContract.connect(user2).stake(amount);

        const stakerAtEnd = await StakingPoolContract.stakers(user2.address);
        expect(stakerAtEnd.stakedTokens).to.be.greaterThan(stakerAtStart.stakedTokens);
        expect(initialBalance).to.be.greaterThan(await TestERC20.balanceOf(user2.address));

        // expect user1 & user2 pending rewards to increase
        expect(await StakingPoolContract.getPendingReward(user1.address)).to.be.greaterThan(user1PendingRewards);
        expect(await StakingPoolContract.getPendingReward(user2.address)).to.be.greaterThan(user2PendingRewards);
    });

    it('Test stake with user3', async function () {
        const initialBalance = await TestERC20.balanceOf(user3.address);
        const stakerAtStart = await StakingPoolContract.stakers(user3.address);
        const user1PendingRewards = await StakingPoolContract.getPendingReward(user1.address);
        const user2PendingRewards = await StakingPoolContract.getPendingReward(user2.address);
        const user3PendingRewards = await StakingPoolContract.getPendingReward(user3.address);
        const amount = ethers.parseUnits('500', 18);
        await TestERC20.connect(user3).approve(StakingPoolContract.target, amount);
        await StakingPoolContract.connect(user3).stake(amount);

        const stakerAtEnd = await StakingPoolContract.stakers(user3.address);
        expect(stakerAtEnd.stakedTokens).to.be.greaterThan(stakerAtStart.stakedTokens);
        expect(initialBalance).to.be.greaterThan(await TestERC20.balanceOf(user3.address));

        // expect user1, user2 & user3 pending rewards to increase
        expect(await StakingPoolContract.getPendingReward(user1.address)).to.be.greaterThan(user1PendingRewards);
        expect(await StakingPoolContract.getPendingReward(user2.address)).to.be.greaterThan(user2PendingRewards);
        expect(await StakingPoolContract.getPendingReward(user3.address)).to.be.greaterThan(user3PendingRewards);
    });

    it('Test claimReward with user1', async function () {
        const initialBalance = await TestERC20.balanceOf(user1.address);
        const stakerAtStart = await StakingPoolContract.stakers(user1.address);
        const user2PendingRewards = await StakingPoolContract.getPendingReward(user2.address);
        const user3PendingRewards = await StakingPoolContract.getPendingReward(user3.address);
        await StakingPoolContract.connect(user1).claimReward();

        const stakerAtEnd = await StakingPoolContract.stakers(user1.address);
        expect(stakerAtEnd.stakedTokens).to.eq(stakerAtStart.stakedTokens); // no change in the staked token amount
        expect(await TestERC20.balanceOf(user1.address)).to.be.greaterThan(initialBalance);

        // expect user1 pending rewards to be null
        expect(await StakingPoolContract.getPendingReward(user1.address)).to.eq(0);

        // expect user2 & user3 pending rewards to stay the same
        expect(await StakingPoolContract.getPendingReward(user2.address)).to.eq(user2PendingRewards);
        expect(await StakingPoolContract.getPendingReward(user3.address)).to.eq(user3PendingRewards);
    });

    it('Test unstake with user1', async function () {
        const initialBalance = await TestERC20.balanceOf(user1.address);
        const stakerAtStart = await StakingPoolContract.stakers(user1.address);
        const user2PendingRewards = await StakingPoolContract.getPendingReward(user2.address);
        const user3PendingRewards = await StakingPoolContract.getPendingReward(user3.address);
        const amount = ethers.parseUnits('250', 18);
        let tx = await StakingPoolContract.connect(user1).unstake(amount);

        const stakerAtEnd = await StakingPoolContract.stakers(user1.address);
        expect(stakerAtStart.stakedTokens).to.be.greaterThan(stakerAtEnd.stakedTokens);
        expect(stakerAtEnd.stakedTokens).to.be.greaterThan(0);
        expect(stakerAtEnd.stakedTokens).to.eq(BigInt(stakerAtStart.stakedTokens) - amount);
        expect(await TestERC20.balanceOf(user1.address)).to.be.greaterThan(initialBalance);

        // expect user2 & user3 pending rewards to increase
        expect(await StakingPoolContract.getPendingReward(user2.address)).to.be.greaterThan(user2PendingRewards);
        expect(await StakingPoolContract.getPendingReward(user3.address)).to.be.greaterThan(user3PendingRewards);
    });

    it('Test donateToPool with owner', async function () {
        const initialBalance = await TestERC20.balanceOf(owner.address);
        const user1PendingRewards = await StakingPoolContract.getPendingReward(user1.address);
        const user2PendingRewards = await StakingPoolContract.getPendingReward(user2.address);
        const user3PendingRewards = await StakingPoolContract.getPendingReward(user3.address);
        const amount = ethers.parseUnits('1000', 18);
        await TestERC20.connect(owner).approve(StakingPoolContract.target, amount);
        await StakingPoolContract.connect(owner).donateToPool(amount);

        const stakerAtEnd = await StakingPoolContract.stakers(owner.address);
        expect(stakerAtEnd.round).to.eq(0);
        expect(stakerAtEnd.stakedTokens).to.eq(0);
        expect(initialBalance).to.be.greaterThan(await TestERC20.balanceOf(owner.address));
        expect(initialBalance).to.eq(BigInt(await TestERC20.balanceOf(owner.address)) + amount);

        // expect user1, user2 & user3 pending rewards to increase
        expect(await StakingPoolContract.getPendingReward(user1.address)).to.be.greaterThan(user1PendingRewards);
        expect(await StakingPoolContract.getPendingReward(user2.address)).to.be.greaterThan(user2PendingRewards);
        expect(await StakingPoolContract.getPendingReward(user3.address)).to.be.greaterThan(user3PendingRewards);
    });

    it('Test stake with user3', async function () {
        const initialBalance = await TestERC20.balanceOf(user3.address);
        const stakerAtStart = await StakingPoolContract.stakers(user3.address);
        const user1PendingRewards = await StakingPoolContract.getPendingReward(user1.address);
        const user2PendingRewards = await StakingPoolContract.getPendingReward(user2.address);
        const user3PendingRewards = await StakingPoolContract.getPendingReward(user3.address);
        const amount = ethers.parseUnits('500', 18);
        await TestERC20.connect(user3).approve(StakingPoolContract.target, amount);
        await StakingPoolContract.connect(user3).stake(amount);

        const stakerAtEnd = await StakingPoolContract.stakers(user3.address);
        expect(stakerAtEnd.stakedTokens).to.be.greaterThan(stakerAtStart.stakedTokens);
        expect(initialBalance).to.be.greaterThan(await TestERC20.balanceOf(user3.address));

        // expect user1 & user2 pending rewards to increase
        expect(await StakingPoolContract.getPendingReward(user1.address)).to.be.greaterThan(user1PendingRewards);
        expect(await StakingPoolContract.getPendingReward(user2.address)).to.be.greaterThan(user2PendingRewards);

        // expect user 3 pending rewards to decrease, because each stake automatically claim the rewards
        expect(user3PendingRewards).to.be.greaterThan(await StakingPoolContract.getPendingReward(user3.address));
    });

    it('Test unstake with all users', async function () {
        const user1InitialBalance = await TestERC20.balanceOf(user1.address);
        const user2InitialBalance = await TestERC20.balanceOf(user2.address);
        const user3InitialBalance = await TestERC20.balanceOf(user3.address);
        const user1StakerAtStart = await StakingPoolContract.stakers(user1.address);
        const user2StakerAtStart = await StakingPoolContract.stakers(user2.address);
        const user3StakerAtStart = await StakingPoolContract.stakers(user3.address);

        await StakingPoolContract.connect(user1).unstake(user1StakerAtStart.stakedTokens);
        await StakingPoolContract.connect(user2).unstake(user2StakerAtStart.stakedTokens);
        await StakingPoolContract.connect(user3).unstake(user3StakerAtStart.stakedTokens);

        const user1StakerAtEnd = await StakingPoolContract.stakers(user1.address);
        const user2StakerAtEnd = await StakingPoolContract.stakers(user2.address);
        const user3StakerAtEnd = await StakingPoolContract.stakers(user3.address);

        expect(user1StakerAtStart.stakedTokens).to.be.greaterThan(user1StakerAtEnd.stakedTokens);
        expect(user2StakerAtStart.stakedTokens).to.be.greaterThan(user2StakerAtEnd.stakedTokens);
        expect(user3StakerAtStart.stakedTokens).to.be.greaterThan(user3StakerAtEnd.stakedTokens);
        expect(user1StakerAtEnd.stakedTokens).to.eq(0);
        expect(user2StakerAtEnd.stakedTokens).to.eq(0);
        expect(user3StakerAtEnd.stakedTokens).to.eq(0);
        expect(await TestERC20.balanceOf(user1.address)).to.be.greaterThan(user1InitialBalance);
        expect(await TestERC20.balanceOf(user2.address)).to.be.greaterThan(user2InitialBalance);
        expect(await TestERC20.balanceOf(user3.address)).to.be.greaterThan(user3InitialBalance);

        // expect user1, user2 & user3 pending rewards to be null
        expect(await StakingPoolContract.getPendingReward(user1.address)).to.eq(0);
        expect(await StakingPoolContract.getPendingReward(user2.address)).to.eq(0);
        expect(await StakingPoolContract.getPendingReward(user3.address)).to.eq(0);
    });

    it('Test setting INVALID pool fees', async function () {
        await expect(
            StakingPoolContract.connect(owner).setFees(20, 20)
        ).to.be.revertedWithCustomError(
            StakingPoolContract,
            'InvalidFees'
        );
    });

    it('Test INVALID stake', async function () {
        await expect(
            StakingPoolContract.connect(owner).stake(ethers.parseUnits('500', 18))
        ).to.be.revertedWithCustomError(
            TestERC20,
            'ERC20InsufficientAllowance'
        );
    });

    it('Test INVALID stake ( approval given, but contract paused )', async function () {
        await StakingPoolContract.connect(owner).pause();
        const amount = ethers.parseUnits('500', 18);
        await TestERC20.connect(owner).approve(StakingPoolContract.target, amount);
        await expect(
            StakingPoolContract.connect(owner).stake(amount)
        ).to.be.revertedWithCustomError(
            StakingPoolContract,
            'EnforcedPause'
        );
        await StakingPoolContract.connect(owner).unpause();
    });

    it('Test INVALID donateToPool', async function () {
        await expect(
            StakingPoolContract.connect(owner).donateToPool(ethers.parseUnits('500', 18))
        ).to.be.revertedWithCustomError(
            StakingPoolContract,
            'InvalidInject'
        );
    });

    it('Test INVALID donateToPool ( approval given, but contract paused )', async function () {
        await StakingPoolContract.connect(owner).pause();
        const amount = ethers.parseUnits('500', 18);
        await TestERC20.connect(owner).approve(StakingPoolContract.target, amount);
        await expect(
            StakingPoolContract.connect(owner).donateToPool(amount)
        ).to.be.revertedWithCustomError(
            StakingPoolContract,
            'EnforcedPause'
        );
        await StakingPoolContract.connect(owner).unpause();
    });

    it('Test INVALID unstake', async function () {
        await expect(
            StakingPoolContract.connect(owner).unstake(ethers.parseUnits('500', 18))
        ).to.be.revertedWithCustomError(
            StakingPoolContract,
            'InvalidAmount'
        );
    });

    it('Test INVALID claimReward', async function () {
        await expect(
            StakingPoolContract.connect(owner).claimReward()
        ).to.be.revertedWithCustomError(
            StakingPoolContract,
            'InvalidRewardClaim'
        );
    });
});