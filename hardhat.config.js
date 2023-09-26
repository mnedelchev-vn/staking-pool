require("@nomicfoundation/hardhat-toolbox");

module.exports = {
    solidity: "0.8.19",
    defaultNetwork: 'hardhat',
    solidity: {
        compilers: [
            {
                version: '0.8.19',
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    }
                }
            }
        ]
    },
    networks: {
        hardhat: {
            allowUnlimitedContractSize: true
        }
    },
    mocha: {
        timeout: 60000
    }
};