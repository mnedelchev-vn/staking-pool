# Staking Pool smart contract

### Project setup commands:
* ```npm install``` - Downloading required packages.
* ```npx hardhat test --network hardhat test/StakingPool.js``` - Testing the `StakingPool.sol` logic.
* ```npx hardhat run scripts/deploy.js --network <network-name>``` - Deploying the `StakingPool.sol` smart contract.

### Purpose:
The Staking Pool is a smart contract where multiple holders of particular ERC20 token can earn passive income based on the amount of tokens that they have been staking. The smart contract has no time restrictions which means that the token holders are allowed to stake, unstake or claim their current rewards at any time. This approach doesn't have hardcoded or flexiable APY, in matter of fact it doesn't have APY at all. The way that rewards are being generated are based on fees which are being collected from every stake or unstake action. Everytime someone join or leave the staking pool he is being charged with small fees which are scattered among the stakers based on their stake. The longer you keep your staking position inside the pool the higher rewards you will generate thanks to the stakers who joined after you.

### Smart contract methods:
* Method `stake` - this method accepts one parameter `_amount` which is the amount of tokens that the `msg.sender` is willing to stake.
* Method `unstake` - this method accepts one parameter `_amount` which is the amount of tokens that the `msg.sender` is willing to unstake.
* Method `claimReward` - this method transfers all the current existing staking rewards to the `msg.sender` address.
* Method `injectIntoPool` - This method accepts on parameter `_amount` and is designed if someone wants to make a donation to current the stakeholders. The `_amount` amount goes directly to the smart contract and is scattered among the stakers based on their stake.
* Method `getPendingReward` - getter method which accepts one parameter `_staker` and is returning all the current existing staking rewards for `_staker` address.
* The current round & staked amount for each user can be taken by the `mapping(address => Staker) public stakers` where the mapping key is the staker address.

### Smart contract Owner methods:
* Method `setFees` - with this method the owner have the permission to update the contract fees, but there is a condition which is protecting stakers that the fees can never be higher than 10 percentages.
* Method `pause` - this is a standard method by OpenZeppelin to active the `Pausable.sol` logic. _( Currently only methods `stake` and `injectIntoPool` have the modifier **whenNotPaused** which means that in the future this smart contract be retired without without restricting stakers from withdrawing their tokens. )_
* Method `unpause` - this is a standard method by OpenZeppelin to deactive the `Pausable.sol` logic.

### Smart contract constructor parameters:
* `_token` - This is the token contract to which the Staking Program will apply. Holders of this token will have the opportunity to take part in the staking.
* `_stakingFee` - this is the fee in percentages that the user will be charged with whenever he is staking particular amount of tokens. _( Example - setting `_stakingFee` to **2** will make every user to pay 2% fee for his staking. )_
* `_unstakingFee` - this is the fee in percentages that the user will be charged with whenever he is unstaking particular amount of tokens. _( Example - setting `_unstakingFee` to **2** will make every user to pay 2% fee for his unstaking. )_


**WARNING!** - This contract is currently supporting only ERC20 tokens. The current version of the smart contract has not being audited by 3rd party and using it will be at your own risk.