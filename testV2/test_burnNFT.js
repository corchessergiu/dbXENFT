const { deployContract } = require("@nomiclabs/hardhat-ethers/types");
const { expect } = require("chai");
const exp = require("constants");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test mintDBXENFT functionality", async function() {
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
        const DBXeNFTAddress = await dbXeNFTFactory.dbxenft()
        DBXeNFT = await ethers.getContractAt("DBXENFT", DBXeNFTAddress, deployer)
    });

    it("Only owner of XENFT can mint DBXeNFT", async function() {
        await xenft.bulkClaimRank(128, 1);

        await expect(dbXeNFTFactory.connect(alice).mintDBXENFT(10001), { value: ethers.utils.parseEther("1") })
            .to.be.revertedWith("You do not own this NFT!")
    })

    it("Sending value less than the required fee will fail DBXeNFT minting attempt", async function() {
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(dbXeNFTFactory.address, 10001)

        await expect(dbXeNFTFactory.mintDBXENFT(10001, { value: 1 }))
            .to.be.revertedWith("Payment less than fee")
    })

    it("Burn a XENFT basic case", async function() {
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(dbXeNFTFactory.address, 10001)

        const balanceBefore = await hre.ethers.provider.getBalance(deployer.address)

        const tx = await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })
        const receipt = await tx.wait()

        const balanceAfter = await hre.ethers.provider.getBalance(deployer.address);

        const DBXeNFTMintedEvent = receipt.events.find(function(el) {
            return el.event == "DBXeNFTMinted"
        })
        const fee = DBXeNFTMintedEvent.args.fee
        const txCost = receipt.effectiveGasPrice.mul(receipt.cumulativeGasUsed)

        expect(balanceAfter).to.equal(balanceBefore.sub(fee).sub(txCost))
        expect(await DBXeNFT.ownerOf(0)).to.equal(deployer.address)
        expect(await dbXeNFTFactory.tokenEntryCycle(0)).to.equal(0)
        // expect(await dbXeNFTFactory.tokenUnderlyingXENFT(0)).to.equal(10001)
        expect(await dbXeNFTFactory.dbxenftEntryPower(0)).to.not.equal(0)
        expect(await xenft.ownerOf(10001)).to.equal(dbXeNFTFactory.address)
    })
})