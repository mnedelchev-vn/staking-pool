require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-foundry");
require("dotenv").config();

module.exports = {
    solidity: "0.8.28",
    defaultNetwork: 'hardhat',
    solidity: {
        compilers: [
            {
                version: '0.8.28',
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
            forking: {
                live: false,
                saveDeployments: false,
                accounts: [],
                url: process.env.RPC_NODE
            }
        }
    },
    mocha: {
        timeout: 60000
    }
};