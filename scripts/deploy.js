// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
    [owner] = await hre.ethers.getSigners();

    const TOKEN_ADDRESS = '';
    const STAKING_FEE = 2; // sample fee
    const UNSTAKING_FEE = 2; // sample fee
    let StakingPoolContract = await hre.ethers.getContractFactory('StakingPool');
    StakingPoolContract = await StakingPoolContract.deploy(
        TOKEN_ADDRESS,
        STAKING_FEE,
        UNSTAKING_FEE
    ); 
    expect(await StakingPoolContract.owner()).to.eq(owner.address);

    console.log('StakingPoolContract deployed at address: ', StakingPoolContract);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
