/** @type import('hardhat/config').HardhatUserConfig */
require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-chai-matchers")

module.exports = {
    solidity: {
        compilers: [{
            version: "0.8.18",
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 1
                }
            }
        }]
    },
    networks: {
        hardhat: {
            allowUnlimitedContractSize: true,
            chainId: 1337, // We set 1337 to make interacting with MetaMask simpler
        }
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS ? true : false,
    },
};