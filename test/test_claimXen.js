const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test xen claiming functionality", async function() {
    let xenft, dbXeNFTFactory, XENContract, DBX, DBXeNFT;
    let alice, bob, carol, dean;
    let dbXeNFTFactoryAlice, dbXeNFTFactoryBob, dbXeNFTFactoryCarol, dbXeNFTFactoryDean
    let xenftAlice, xenftBob, xenftCarol, xenftDean
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

        dbXeNFTFactory = await DBXeNFTFactory.deploy(DBX.address, xenft.address, XENContract.address, deployer.address);
        await dbXeNFTFactory.deployed();
        const DBXeNFTAddress = await dbXeNFTFactory.dbxenft()
        DBXeNFT = await ethers.getContractAt("DBXENFT", DBXeNFTAddress, deployer)

        dbXeNFTFactoryAlice = dbXeNFTFactory.connect(alice)
        dbXeNFTFactoryBob = dbXeNFTFactory.connect(bob)
        dbXeNFTFactoryCarol = dbXeNFTFactory.connect(carol)
        dbXeNFTFactoryDean = dbXeNFTFactory.connect(dean)

        xenftAlice = xenft.connect(alice)
        xenftBob = xenft.connect(bob)
        xenftCarol = xenft.connect(carol)
        xenftDean = xenft.connect(dean)

        DBX.transfer(alice.address, ethers.utils.parseEther("10000"))
        DBX.transfer(bob.address, ethers.utils.parseEther("10000"))
        DBX.transfer(carol.address,ethers.utils.parseEther("10000"))
        DBX.transfer(dean.address, ethers.utils.parseEther("10000"))

        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(alice).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(bob).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(carol).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(dean).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        
    });

    it("Basic xen claiming case", async function() {
        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactory.claimXen(1)

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactory.mintDBXENFT(10002  , {value: ethers.utils.parseEther("1")})

        expect(await XENContract.balanceOf(deployer.address)).to.not.equal(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(1)).to.equal(ethers.utils.parseEther("1"))
        expect(await dbXeNFTFactory.summedCyclePowers(1)).to.equal(
            (await dbXeNFTFactory.rewardPerCycle(1))
            .add(await dbXeNFTFactory.baseDBXeNFTPower(1))
        )

        await expect(dbXeNFTFactory.claimXen(1))
            .to.be.revertedWith("XENFT: Already redeemed")
    })

    it("Xen claiming will make DXN extra power apply to a 1 base power", async function() {
        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactory.stake(ethers.utils.parseEther("100"), 1, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactory.claimXen(1)


        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactory.mintDBXENFT(10002, {value: ethers.utils.parseEther("1")})

        expect(await XENContract.balanceOf(deployer.address)).to.not.equal(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(1)).to.equal(ethers.utils.parseEther("1"))
        expect(await dbXeNFTFactory.summedCyclePowers(1)).to.equal(
            (await dbXeNFTFactory.rewardPerCycle(1))
            .add(ethers.utils.parseEther("2"))
        )
    })

    it("Xen claimed during inactive cycle will apply DBXeNFT power cut in the next active cycle", async function(){
        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10001)

        await dbXeNFTFactory.mintDBXENFT(10001, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const tx = await dbXeNFTFactory.claimXen(1)
        const receipt = await tx.wait()
        console.log(receipt.gasUsed)

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactory.mintDBXENFT(10002  , {value: ethers.utils.parseEther("1")})

        expect(await XENContract.balanceOf(deployer.address)).to.not.equal(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(1)).to.equal(ethers.utils.parseEther("1"))
        expect(await dbXeNFTFactory.summedCyclePowers(2)).to.equal(
            (await dbXeNFTFactory.rewardPerCycle(2))
            .add(ethers.utils.parseEther("1"))
        )
    })
})