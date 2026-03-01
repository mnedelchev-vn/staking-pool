// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract StakingPool is Ownable, Pausable {
    using SafeERC20 for IERC20;

    uint64 constant public SCALING = 10 ** 18;
    uint256 constant public FEE_DENOMINATOR = 10000;
    IERC20 public immutable token;
    uint16 public stakingFee; // percentage e.g. 200 for 2%
    uint16 public unstakingFee; // percentage e.g. 200 for 2%
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
    error InvalidInject();
    error InvalidRewardClaim();
    error InvalidRecover();

    constructor(address _token, uint16 _stakingFee, uint16 _unstakingFee) Ownable(msg.sender) {
        token = IERC20(_token);

        setFees(_stakingFee, _unstakingFee);
    }

    event Staked(address staker, uint256 tokens, uint256 fee);
    event Unstaked(address staker, uint256 tokens, uint256 fee);
    event Payout(uint256 round, uint256 tokens, address sender);
    event ClaimReward(address staker, uint256 reward);
    event Recovered(address token, uint256 amount);

    /*
     * CONTRACT OWNER
     */
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setFees(uint16 _stakingFee, uint16 _unstakingFee) public onlyOwner {
        if (_stakingFee > FEE_DENOMINATOR / 10 || _unstakingFee > FEE_DENOMINATOR / 10) revert InvalidFees();

        stakingFee = _stakingFee;
        unstakingFee = _unstakingFee;
    }

    function recover(address _token, uint256 _amount) public onlyOwner {
        if (_token == address(0)) {
            (bool success, ) = owner().call{value: _amount}("");
            require(success, InvalidRecover());
        } else {
            IERC20(_token).safeTransfer(owner(), _amount);
            require(IERC20(token).balanceOf(address(this)) >= totalStakes, InvalidRecover());
        }

        emit Recovered(_token, _amount);
    }
    /*
     * /CONTRACT OWNER
     */

    /// @notice Staking into the smart contract
    /// @param _amount The staking token amount
    function stake(uint256 _amount) external whenNotPaused {
        require(_amount > 0, InvalidAmount());
        token.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 _fee;
        if (totalStakes > 0) {
            _fee = (_amount * stakingFee) / FEE_DENOMINATOR;
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
            token.safeTransfer(msg.sender, pendingReward);
            emit ClaimReward(msg.sender, pendingReward);
        }

        emit Staked(msg.sender, _amount - _fee, _fee);
    }

    /// @notice Claiming currently generated staking rewards
    function claimReward() external {
        uint256 pendingReward = getPendingReward(msg.sender);
        if (pendingReward > 0) {
            stakers[msg.sender].round = round; // update the round
            token.safeTransfer(msg.sender, pendingReward);
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
            _fee = (_amount * unstakingFee) / FEE_DENOMINATOR;
            _addPayout(_fee);
        }

        // if existing rewards then add them to the unstaking amount
        uint256 unstakingAmount = _amount - _fee;
        if (pendingReward > 0) {
            unstakingAmount = unstakingAmount + pendingReward;
            emit ClaimReward(msg.sender, pendingReward);
        }

        // sending to user desired token amount minus his unstacking fee
        token.safeTransfer(msg.sender, unstakingAmount);

        emit Unstaked(msg.sender, _amount - _fee, _fee);
    }

    /// @notice Injecting amount of tokens into smart contract which are getting scattered among the stakers based on their stake
    /// @param _amount The injecting token amount
    function donateToPool(uint256 _amount) external whenNotPaused {
        if (totalStakes > 0) {
            token.safeTransferFrom(msg.sender, address(this), _amount);
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