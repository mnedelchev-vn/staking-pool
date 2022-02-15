# Staking Program smart contract

## Purpose
The Staking Program smart contract is a place where multiple holders of particular ERC20 token are earning passive income based on the amount of tokens that they have been staking. The smart contract has no time restrictions which means that the token holders are allowed to stake, unstake or claim their current rewards at any time.

## Public methods
* Method `stake` - this method accepts one parameter `_tokens_amount` which is basically the amount of tokens that the `msg.sender` is willing to stake.
* Method `unstake` - this method accepts one parameter `_tokens_amount` which is basically the amount of tokens that the `msg.sender` is willing to unstake.
* Method `claimReward` - this method transfers all the current existing staking rewards to the `msg.sender` address.
* Method `getPendingReward` - getter method which accepts one parameter `_staker` and is returning all the current existing staking rewards for `_staker` address.
* Method `addRewards` - This method accepts on parameter `_tokens_amount` and is designed if someone wants to make a donation to the stakeholders. The `_tokens_amount` amount go directly to the smart contrac total stake and are scattered among the stakers based on their stake.

## Contract owner methods
* Method `stopUnstopStaking` - this method is built to "retire" the staking smart contract whenever it's not needed anymore. However this method shuts down only future staking actions. Once stopped from staking, the existing stakers in the Staking Program will still be able to withdraw their stakes and the current rewards ( if they have any at the time of unstaking ).
* Method `setFees` - this method is existing so the owner have the permission to update the contract fees, but there is a condition which is protecting token owners that the fees can never be higher than 10 percentages.
* Method `setAcceleratorAddress` - by default variable `acceleratorAddress` is set to 0x0 and this logic is not working by the time of deploying contract. This logic is created if in the future the owner of the Staking Program manages to find a way to successfully iterate with another contract in order to better addoption the Staking Program smart contract.

#### Required parameters before deploying the contract:
* `_erc20token_address` - .
* `_stakingFee` - this is the fee in percentages that the user will be charged with whenever he is staking particular amount of tokens.
* `_unstakingFee` - this is the fee in percentages that the user will be charged with whenever he is unstaking particular amount of tokens.


**WARNING!** - This contract is currently supporting only ERC20 tokens with **0 decimals**. If you want it to support ERC20 tokens with decimals then you will have to fork it and modify it at your own risk.