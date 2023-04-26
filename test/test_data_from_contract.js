const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test claim fee functionality", async function() {
    let xenft, DBXENFT, XENContract, aliceInstance, bobInstance, deanInstance;
    let alice, bob, carol, dean;
    beforeEach("Set enviroment", async() => {
        [deployer, alice, bob, carol, dean, messageReceiver, feeReceiver] = await ethers.getSigners();

        const lib = await ethers.getContractFactory("MathXEN");
        const library = await lib.deploy();

        const xenContract = await ethers.getContractFactory("XENCryptoMockMint", {
            libraries: {
                MathXEN: library.address
            }
        });

        XENContract = await xenContract.deploy();
        await XENContract.deployed();

        const MintInfo = await ethers.getContractFactory("MintInfo", deployer)
        const mintinfo = await MintInfo.deploy()
        await mintinfo.deployed()

        const DateTime = await ethers.getContractFactory("DateTime", deployer)
        const datetime = await DateTime.deploy()
        await datetime.deployed()

        const StringsData = await ethers.getContractFactory("StringData", deployer)
        const stringsdata = await StringsData.deploy()
        await stringsdata.deployed()

        const Metadata = await ethers.getContractFactory("Metadata", {
            signer: deployer,
            libraries: {
                MintInfo: mintinfo.address,
                DateTime: datetime.address,
                StringData: stringsdata.address
            }
        })

        const metadata = await Metadata.deploy()
        await metadata.deployed()

        const XENFT = await ethers.getContractFactory("XENTorrent", {
            signer: deployer,
            libraries: {
                MintInfo: mintinfo.address,
                Metadata: metadata.address
            }
        });

        let burnRates_ = [0, ethers.utils.parseEther("250000000"), ethers.utils.parseEther("500000000"),
            ethers.utils.parseEther("1000000000"), ethers.utils.parseEther("2000000000"),
            ethers.utils.parseEther("5000000000"), ethers.utils.parseEther("10000000000")
        ]
        let tokenLimits_ = [0, 0, 10000, 6000, 3000, 1000, 100]

        xenft = await XENFT.deploy(
            XENContract.address, burnRates_, tokenLimits_,
            0,
            ethers.constants.AddressZero, ethers.constants.AddressZero
        )
        await xenft.deployed();

        const dbXENFT = await ethers.getContractFactory("dbXENFT", {
            libraries: {
                MintInfo: mintinfo.address
            }
        });

        DBXENFT = await dbXENFT.deploy(xenft.address, XENContract.address);
        await DBXENFT.deployed();
    });

    it("Claim fees", async() => {
        await XENContract.approve(xenft.address, ethers.utils.parseEther("100000000000000000"))
        await xenft.bulkClaimRank(1, 1);
        // await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("250000000"));
        // await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("500000000"));
        // await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("1000000000"));
        // await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("2000000000"));
        // await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("250000000"));
        // await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("5000000000"));
        // await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("10000000000"));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 + 1])
        await hre.ethers.provider.send("evm_mine")

        console.log(await xenft.balanceOf(deployer.address));
        console.log(await xenft.ownedTokens())

        console.log("*************");
        await DBXENFT.burnNFT(10001);
        // console.log("*************");
        // console.log("*************");
        // await DBXENFT.burnNFT(6001);
        // console.log("*************");
        // console.log("*************");
        // await DBXENFT.burnNFT(3001);
        // console.log("*************");
        // console.log("*************");
        // await DBXENFT.burnNFT(1001);
        // console.log("*************");
        // console.log("*************");
        // await DBXENFT.burnNFT(10002);
        // console.log("*************");
        // console.log("*************");
        // await DBXENFT.burnNFT(101);
        // console.log("*************");
        // console.log("*************");
        // await DBXENFT.burnNFT(1);
        // console.log("*************");
    });
});