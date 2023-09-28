const { deployContract } = require("@nomiclabs/hardhat-ethers/types");
const { expect } = require("chai");
const exp = require("constants");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test mintDBXENFT functionality", async function() {
    let xenft, dbXeNFTFactory, XENContract, DBX, DBXeNFT;
    let alice, bob, carol, dean;
    let dbXeNFTFactoryAlice, xenftAlice;
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

        await xenft.bulkClaimRank(1, 1);
        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")
        await xenft.bulkClaimMintReward(10001, deployer.address);

        const DBXeNFTFactory = await ethers.getContractFactory("DBXeNFTFactory", {
            libraries: {
                MintInfo: mintinfo.address
            }
        });

        dbXeNFTFactory = await DBXeNFTFactory.deploy(DBX.address, xenft.address, XENContract.address, feeReceiver.address);
        await dbXeNFTFactory.deployed();
        const DBXeNFTAddress = await dbXeNFTFactory.dbxenft()
        DBXeNFT = await ethers.getContractAt("DBXENFT", DBXeNFTAddress, deployer)

        dbXeNFTFactoryAlice = dbXeNFTFactory.connect(alice)
        xenftAlice = xenft.connect(alice)
        DBX.transfer(alice.address, ethers.utils.parseEther("10000"))

        await DBX.connect(alice).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
    });

    it("Only owner of XENFT can mint DBXeNFT", async function() {
        await xenft.bulkClaimRank(128, 1);

        await expect(dbXeNFTFactory.connect(alice).mintDBXENFT(10001), {value: ethers.utils.parseEther("1")})
            .to.be.revertedWith("You do not own this NFT!")
    })

    it("Sending value less than the required fee will fail DBXeNFT minting attempt", async function() {
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(dbXeNFTFactory.address, 10001)

        await expect(dbXeNFTFactory.mintDBXENFT(10001, {value: 1}))
            .to.be.revertedWith("Payment less than fee")
    })

    it("Burn a XENFT basic case", async function() {
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(dbXeNFTFactory.address, 10002)

        const balanceBefore = await hre.ethers.provider.getBalance(deployer.address)
        const feeReceiverBefore = await hre.ethers.provider.getBalance(feeReceiver.address);

        const tx = await dbXeNFTFactory.mintDBXENFT(10002, {value: ethers.utils.parseEther("1")})
        const receipt = await tx.wait()
        const balanceAfter = await hre.ethers.provider.getBalance(deployer.address);
        const feeReceiverAfter = await hre.ethers.provider.getBalance(feeReceiver.address);

        const DBXeNFTMintedEvent = receipt.events.find(function(el) {
            return el.event == "DBXeNFTMinted"
        })
        const fee = DBXeNFTMintedEvent.args.fee
        const txCost = receipt.effectiveGasPrice.mul(receipt.cumulativeGasUsed)

        const storageAddress = await dbXeNFTFactory.dbxenftUnderlyingStorage(1)

        expect(balanceAfter).to.equal(balanceBefore.sub(fee).sub(txCost))
        expect(feeReceiverAfter.sub(feeReceiverBefore)).to.equal(fee.mul(BigNumber.from(25)).div(BigNumber.from(1000)))
        expect(await DBXeNFT.ownerOf(1)).to.equal(deployer.address)
        expect(await dbXeNFTFactory.tokenEntryCycle(1)).to.equal(0)
        expect(await dbXeNFTFactory.dbxenftUnderlyingXENFT(1)).to.equal(10002)
        expect(await dbXeNFTFactory.dbxenftEntryPower(1)).to.not.equal(0)
        expect(await xenft.ownerOf(10002)).to.equal(storageAddress)
    })

    // it("Dev fee is 2.5% and is sent straight to dev address", async function() {
    //     await xenftAlice.bulkClaimRank(64, 7)
    //     await xenftAlice.approve(dbXeNFTFactory.address, 10001)

    //     const deployerBalanceBefore =  await hre.ethers.provider.getBalance(deployer.address)

    //     const aliceTx = await dbXeNFTFactoryAlice.mintDBXENFT(10001, {value: ethers.utils.parseEther("1")})

    //     const deployerBalanceAfter =  await hre.ethers.provider.getBalance(deployer.address)
    //     const deployerFeeReceived = deployerBalanceAfter.sub(deployerBalanceBefore)

    //     let aliceReceipt = await aliceTx.wait()
    //     let aliceDBXeNFTMintedEvent = aliceReceipt.events.find(function(el) {
    //         return el.event == "DBXeNFTMinted"
    //     })
    //     let aliceFeesPaid = aliceDBXeNFTMintedEvent.args.fee

    //     expect(deployerFeeReceived).to.equal(aliceFeesPaid.mul(BigNumber.from(25)).div(BigNumber.from(1000)))
    // })

    it("Mint a DBXENFT using a redeemed XENFT(inactive cycle)", async function() {
        await xenft.bulkClaimRank(1, 1);
        await xenft.approve(dbXeNFTFactory.address, 10002)

        await xenftAlice.bulkClaimRank(64, 7)
        await xenftAlice.approve(dbXeNFTFactory.address, 10003)

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")
        
        await xenft.bulkClaimMintReward(10002, deployer.address);

        

        await dbXeNFTFactoryAlice.mintDBXENFT(10003, {value: ethers.utils.parseEther("1")})

        const balanceBefore = await hre.ethers.provider.getBalance(deployer.address)
        const feeReceiverBefore = await hre.ethers.provider.getBalance(feeReceiver.address);
        const tx = await dbXeNFTFactory.mintDBXENFT(10002, {value: ethers.utils.parseEther("1")})
        const receipt = await tx.wait()

        const balanceAfter = await hre.ethers.provider.getBalance(deployer.address);
        const feeReceiverAfter = await hre.ethers.provider.getBalance(feeReceiver.address);

        const DBXeNFTMintedEvent = receipt.events.find(function(el) {
            return el.event == "DBXeNFTMinted"
        })
        const fee = DBXeNFTMintedEvent.args.fee
        const txCost = receipt.effectiveGasPrice.mul(receipt.cumulativeGasUsed)

        const storageAddress = await dbXeNFTFactory.dbxenftUnderlyingStorage(2)

        expect(balanceAfter).to.equal(balanceBefore.sub(fee).sub(txCost))
        expect(feeReceiverAfter.sub(feeReceiverBefore)).to.equal(fee.mul(BigNumber.from(25)).div(BigNumber.from(1000)))
        expect(await DBXeNFT.ownerOf(1)).to.equal(deployer.address)
        expect(await dbXeNFTFactory.tokenEntryCycle(1)).to.equal(0)
        expect(await dbXeNFTFactory.dbxenftUnderlyingXENFT(1)).to.equal(10002)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(1)).to.equal(ethers.utils.parseEther("1"))
        expect(await xenft.ownerOf(10002)).to.equal(storageAddress)
    })

    it("Mint a DBXENFT using a redeemed XENFT(active cycle)", async function() {
        await xenft.bulkClaimRank(1, 1);
        await xenft.approve(dbXeNFTFactory.address, 10002)

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.bulkClaimMintReward(10002, deployer.address);

        const balanceBefore = await hre.ethers.provider.getBalance(deployer.address)
        const feeReceiverBefore = await hre.ethers.provider.getBalance(feeReceiver.address);

        const tx = await dbXeNFTFactory.mintDBXENFT(10002, {value: ethers.utils.parseEther("1")})
        const receipt = await tx.wait()

        const balanceAfter = await hre.ethers.provider.getBalance(deployer.address);
        const feeReceiverAfter = await hre.ethers.provider.getBalance(feeReceiver.address);

        const DBXeNFTMintedEvent = receipt.events.find(function(el) {
            return el.event == "DBXeNFTMinted"
        })
        const fee = DBXeNFTMintedEvent.args.fee
        const txCost = receipt.effectiveGasPrice.mul(receipt.cumulativeGasUsed)

        const storageAddress = await dbXeNFTFactory.dbxenftUnderlyingStorage(1)

        expect(balanceAfter).to.equal(balanceBefore.sub(fee).sub(txCost))
        expect(feeReceiverAfter.sub(feeReceiverBefore)).to.equal(fee.mul(BigNumber.from(25)).div(BigNumber.from(1000)))
        expect(await DBXeNFT.ownerOf(1)).to.equal(deployer.address)
        expect(await dbXeNFTFactory.tokenEntryCycle(1)).to.equal(0)
        expect(await dbXeNFTFactory.dbxenftUnderlyingXENFT(1)).to.equal(10002)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(1)).to.equal(ethers.utils.parseEther("1"))
        expect(await xenft.ownerOf(10002)).to.equal(storageAddress)
    })
})