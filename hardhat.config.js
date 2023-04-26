/** @type import('hardhat/config').HardhatUserConfig */
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
    solidity: "0.8.18",
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