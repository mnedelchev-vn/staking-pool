// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract StakingPool is Ownable, Pausable {
    uint64 constant private SCALING = 10 ** 18;
    IERC20 public token;
    uint8 public stakingFee; // percentage
    uint8 public unstakingFee; // percentage
    uint256 public round = 1;
    uint256 public totalStakes;
    uint256 public totalDividends;
    uint256 public scaledRemainder;

    struct Staker {
        uint256 stakedTokens;
        uint256 round;
    }

    mapping(address => Staker) public stakers;
    mapping(uint256 => uint256) public payouts;

    error InvalidFees();
    error InvalidAmount();
    error InvalidTransfer();
    error InvalidTransferFrom();
    error InvalidInject();
    error InvalidRewardClaim();

    constructor(address _token, uint8 _stakingFee, uint8 _unstakingFee) Ownable(msg.sender) {
        token = IERC20(_token);
        stakingFee = _stakingFee;
        unstakingFee = _unstakingFee;
    }

    event Staked(address staker, uint256 tokens, uint256 fee);
    event Unstaked(address staker, uint256 tokens, uint256 fee);
    event Payout(uint256 round, uint256 tokens, address sender);
    event ClaimReward(address staker, uint256 reward);

    /*
     * CONTRACT OWNER
     */
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setFees(uint8 _stakingFee, uint8 _unstakingFee) external onlyOwner {
        if (_stakingFee > 10 || _unstakingFee > 10) revert InvalidFees();

        stakingFee = _stakingFee;
        unstakingFee = _unstakingFee;
    }
    /*
     * /CONTRACT OWNER
     */

    /// @notice Staking into the smart contract
    /// @param _amount The staking token amount
    function stake(uint256 _amount) external whenNotPaused {
        if (_amount <= 0) revert InvalidAmount();
        if (!token.transferFrom(msg.sender, address(this), _amount)) revert InvalidTransferFrom();

        uint256 _fee;
        if (totalStakes > 0) {
            _fee = (_amount * stakingFee) / 100;
        }

        uint256 pendingReward = getPendingReward(msg.sender);
        stakers[msg.sender].round = round;
        // saving user staked tokens minus the staking fee
        stakers[msg.sender].stakedTokens = stakers[msg.sender].stakedTokens + _amount - _fee;

        // adding this user stake to the totalStakes
        totalStakes = totalStakes + _amount - _fee;

        // if fee then spread it in the staking pool
        if (_fee > 0) {
            _addPayout(_fee);
        }

        // if existing rewards then send them to the staker
        if (pendingReward > 0) {
            if (!token.transfer(msg.sender, pendingReward)) revert InvalidRewardClaim();
            emit ClaimReward(msg.sender, pendingReward);
        }

        emit Staked(msg.sender, _amount - _fee, _fee);
    }

    /// @notice Claiming currently generated staking rewards
    function claimReward() external {
        uint256 pendingReward = getPendingReward(msg.sender);
        if (pendingReward > 0) {
            stakers[msg.sender].round = round; // update the round
            if (!token.transfer(msg.sender, pendingReward)) revert InvalidRewardClaim();
            emit ClaimReward(msg.sender, pendingReward);
        } else {
            revert InvalidRewardClaim();
        }
    }

    /// @notice Unstaking from the smart contract
    /// @param _amount The unstaking token amount
    function unstake(uint256 _amount) external {
        if (_amount <= 0 || stakers[msg.sender].stakedTokens < _amount) revert InvalidAmount(); 

        uint256 pendingReward = getPendingReward(msg.sender);
        stakers[msg.sender].round = round;
        stakers[msg.sender].stakedTokens = stakers[msg.sender].stakedTokens - _amount;

        // calculating this user unstaking fee based on the tokens amount that user want to unstake
        totalStakes = totalStakes - _amount;

        // if totalStakes then spread the fee in the staking pool
        uint256 _fee;
        if (totalStakes > 0) {
            _fee = (_amount * unstakingFee) / 100;
            _addPayout(_fee);
        }

        // if existing rewards then add them to the unstaking amount
        uint256 unstakingAmount = _amount - _fee;
        if (pendingReward > 0) {
            unstakingAmount = unstakingAmount + pendingReward;
            emit ClaimReward(msg.sender, pendingReward);
        }

        // sending to user desired token amount minus his unstacking fee
        if (!token.transfer(msg.sender, unstakingAmount)) revert InvalidTransfer();

        emit Unstaked(msg.sender, _amount - _fee, _fee);
    }

    /// @notice Injecting amount of tokens into smart contract which are getting scattered among the stakers based on their stake
    /// @param _amount The injecting token amount
    function donateToPool(uint256 _amount) external whenNotPaused {
        if (totalStakes > 0) {
            if (!token.transferFrom(msg.sender, address(this), _amount)) revert InvalidInject();
            _addPayout(_amount);
        } else {
            revert InvalidInject();
        }
    }
    
    /// @notice Private method which serve for internal dividends calculations
    /// @param _fee The calculated fee based on user staking or unstaking amount
    function _addPayout(uint256 _fee) private {
        uint256 available = (_fee * SCALING) + scaledRemainder;
        uint256 dividendPerToken = available / totalStakes;
        scaledRemainder = available % totalStakes;

        totalDividends = totalDividends + dividendPerToken;
        payouts[round] = payouts[round - 1] + dividendPerToken;
        round+=1;

        emit Payout(round, _fee, msg.sender);
    }

    /// @notice Getted method which is returning all the current pending rewards for a staker
    /// @param _staker The staker address
    function getPendingReward(address _staker) public view returns(uint256) {
        uint stakerRound = stakers[_staker].round;
        if (stakerRound > 0) {
            stakerRound-=1;
        }
        return ((totalDividends - payouts[stakerRound]) * stakers[_staker].stakedTokens) / SCALING;
    }
}

// MN bby ¯\_(ツ)_/¯