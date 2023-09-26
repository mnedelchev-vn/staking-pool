// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Token is ERC20, Ownable {
    constructor() ERC20("MyToken", "TKN") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}