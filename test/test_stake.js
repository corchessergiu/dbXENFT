const { deployContract } = require("@nomiclabs/hardhat-ethers/types");
const { expect } = require("chai");
const exp = require("constants");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test stake functionality", async function() {
    let xenft, dbXeNFTFactory, XENContract, DBX, DBXeNFT;
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

        const dbxContract = await ethers.getContractFactory("DBXenERC20");
        DBX = await dbxContract.deploy();
        await DBX.deployed();

        xenft = await XENFT.deploy(
            XENContract.address, burnRates_, tokenLimits_,
            0,
            ethers.constants.AddressZero, ethers.constants.AddressZero
        )
        await xenft.deployed();

        const DBXeNFTFactory = await ethers.getContractFactory("DBXeNFTFactory", {
            libraries: {
                MintInfo: mintinfo.address
            }
        });

        dbXeNFTFactory = await DBXeNFTFactory.deploy(DBX.address, xenft.address, XENContract.address);
        await dbXeNFTFactory.deployed();
        const DBXeNFTAddress = await dbXeNFTFactory.DBXENFTInstance()
        DBXeNFT = await ethers.getContractAt("DBXENFT", DBXeNFTAddress, deployer)
    });

    it("Only owner of DBXeNFT may stake on it", async function() {
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(dbXeNFTFactory.address, 10001)

        const tx = await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})

        await expect(dbXeNFTFactory.connect(alice).stake(ethers.utils.parseEther("1"), 0))
            .to.be.revertedWith("You do not own this NFT!")
    })

    it("Sending value less than the required fee will fail staking attempt", async function() {
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(dbXeNFTFactory.address, 10001)

        const tx = await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})

        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("2000"))
        await dbXeNFTFactory.stake(ethers.utils.parseEther("1000"), 0, {value: ethers.utils.parseEther("1")})

        await expect(dbXeNFTFactory.stake(ethers.utils.parseEther("1000"), 0,
            {value: ethers.utils.parseEther("1").sub(BigNumber.from("1"))}))
            .to.be.revertedWith("Value less than staking fee")
    })

    it.only("Stake 1000 DXN basic case", async function() {
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(dbXeNFTFactory.address, 10001)

        const tx = await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})

        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"))
        await dbXeNFTFactory.stake(ethers.utils.parseEther("1000"), 0, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactory.stake(ethers.utils.parseEther("1"), 0, {value: ethers.utils.parseEther("0.001")})
        const basePow = await dbXeNFTFactory.baseDBXeNFTPower(0)
        expect(await dbXeNFTFactory.DBXeNFTPower(0)).to.equal(basePow.mul(BigNumber.from(2)))
    })
})