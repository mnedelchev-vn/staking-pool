// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const { ethers } = require("hardhat");
const { expect } = require("chai");

async function main() {
    const [owner] = await ethers.getSigners();

    const TestERC20 = await ethers.deployContract("TestERC20");
    await TestERC20.waitForDeployment();

    expect(await TestERC20.owner()).to.eq(owner.address);
    console.log('TestERC20 deployed at address: ', TestERC20.target);

    let balanceOfOwner = await TestERC20.balanceOf(owner.address);

    let tx = await TestERC20.mint(owner.address, ethers.parseUnits('10', 18));
    await tx.wait(1);

    expect(await TestERC20.balanceOf(owner.address)).to.greaterThan(balanceOfOwner);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
