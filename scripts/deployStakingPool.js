// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers } = require("hardhat");
const { expect } = require("chai");

async function main() {
    [owner] = await ethers.getSigners();

    const TOKEN_ADDRESS = '0x03F7F064E6ceD8e154e3FdAAF92DcCC4e818E97B';
    const STAKING_FEE = 2; // sample fee
    const UNSTAKING_FEE = 2; // sample fee

    if (!ethers.isAddress(TOKEN_ADDRESS)) {
        return console.error('Invalid TOKEN_ADDRESS value.');
    }

    StakingPoolContract = await ethers.deployContract("StakingPool", [
        TOKEN_ADDRESS,
        STAKING_FEE,
        UNSTAKING_FEE
    ]);
    await StakingPoolContract.waitForDeployment();

    expect(await StakingPoolContract.owner()).to.eq(owner.address);
    console.log('StakingPoolContract deployed at address: ', StakingPoolContract.target);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
