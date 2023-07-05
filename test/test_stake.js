const { deployContract } = require("@nomiclabs/hardhat-ethers/types");
const { expect } = require("chai");
const exp = require("constants");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test stake functionality", async function() {
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

        dbXeNFTFactory = await DBXeNFTFactory.deploy(DBX.address, xenft.address, XENContract.address);
        await dbXeNFTFactory.deployed();
        const DBXeNFTAddress = await dbXeNFTFactory.DBXENFTInstance()
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

        await DBX.connect(alice).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(bob).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(carol).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(dean).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        
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

    it("Stake 1000 DXN basic case", async function() {
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

    it("Multiple entries and stakings coming from different addresses", async function() {
        await xenft.bulkClaimRank(128, 1)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(64, 7)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("1000"), 1, {value: ethers.utils.parseEther("1")})
        

        await xenftBob.bulkClaimRank(100, 100)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("100"), 2, {value: ethers.utils.parseEther("1")})

        await xenftCarol.bulkClaimRank(32, 100)
        await xenftCarol.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryCarol.burnNFT(10004, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther("500"), 3, {value: ethers.utils.parseEther("1")})
        
        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const totalEntryPow = await dbXeNFTFactory.totalPowerPerCycle(0)
        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)

        const deployerEntryPow = await dbXeNFTFactory.tokenEntryPower(0)
        await dbXeNFTFactory.claimFees(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(0)).to.equal(deployerEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const aliceEntryPow = await dbXeNFTFactory.tokenEntryPower(1)
        await dbXeNFTFactoryAlice.claimFees(1)
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceBasePow).to.equal(aliceEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))
        
        const bobEntryPow = await dbXeNFTFactory.tokenEntryPower(2)
        await dbXeNFTFactoryBob.claimFees(2)
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobBasePow).to.equal(bobEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const carolEntryPow = await dbXeNFTFactory.tokenEntryPower(3)
        await dbXeNFTFactoryCarol.claimFees(3)
        const carolBasePow = await dbXeNFTFactory.baseDBXeNFTPower(3)
        expect(carolBasePow).to.equal(carolEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactory.burnNFT(10005, {value: ethers.utils.parseEther("1")})

        const ePow21 = ethers.utils.parseEther("1000")
        const aliceDBXeNFTPow = aliceBasePow.mul(ethers.utils.parseEther("1000")).div(ePow21)
        const bobDBXeNFTPow = bobBasePow.mul(ethers.utils.parseEther("100")).div(ePow21)
        const carolDBXeNFTPow = carolBasePow.mul(ethers.utils.parseEther("500")).div(ePow21)
        const newRewardPow = ethers.utils.parseEther("10000").add(ethers.utils.parseEther("10000").div(BigNumber.from("100")))
        expect(await dbXeNFTFactory.summedCycleStakes(1)).to.equal(aliceDBXeNFTPow
            .add(bobDBXeNFTPow)
            .add(carolDBXeNFTPow)
            .add(newRewardPow)
            .add(await dbXeNFTFactory.summedCycleStakes(0)))
        // const balanceAfter = await hre.ethers.provider.getBalance(dbXeNFTFactory.address)
        // console.log(balanceAfter)
    })

    it("Stake power should apply in the next active cycle following an inactive one", async function(){
        await xenft.bulkClaimRank(80, 2)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(50, 40)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("1"), 1, {value: ethers.utils.parseEther("1")})
        

        await xenftBob.bulkClaimRank(100, 90)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("23"), 2, {value: ethers.utils.parseEther("1")})

        await xenftCarol.bulkClaimRank(2, 100)
        await xenftCarol.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryCarol.burnNFT(10004, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther("7"), 3, {value: ethers.utils.parseEther("1")})
        
        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 2])
        await hre.ethers.provider.send("evm_mine")

        const totalEntryPow = await dbXeNFTFactory.totalPowerPerCycle(0)
        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)

        const deployerEntryPow = await dbXeNFTFactory.tokenEntryPower(0)
        await dbXeNFTFactory.claimFees(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(0)).to.equal(deployerEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const aliceEntryPow = await dbXeNFTFactory.tokenEntryPower(1)
        await dbXeNFTFactoryAlice.claimFees(1)
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceBasePow).to.equal(aliceEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))
        
        const bobEntryPow = await dbXeNFTFactory.tokenEntryPower(2)
        await dbXeNFTFactoryBob.claimFees(2)
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobBasePow).to.equal(bobEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const carolEntryPow = await dbXeNFTFactory.tokenEntryPower(3)
        await dbXeNFTFactoryCarol.claimFees(3)
        const carolBasePow = await dbXeNFTFactory.baseDBXeNFTPower(3)
        expect(carolBasePow).to.equal(carolEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactory.burnNFT(10005, {value: ethers.utils.parseEther("1")})

        const ePow21 = ethers.utils.parseEther("1000")
        const aliceDBXeNFTPow = aliceBasePow.mul(ethers.utils.parseEther("1")).div(ePow21)
        const bobDBXeNFTPow = bobBasePow.mul(ethers.utils.parseEther("23")).div(ePow21)
        const carolDBXeNFTPow = carolBasePow.mul(ethers.utils.parseEther("7")).div(ePow21)
        const newRewardPow = ethers.utils.parseEther("10000").add(ethers.utils.parseEther("10000").div(BigNumber.from("100")))
        expect(await dbXeNFTFactory.summedCycleStakes(2)).to.equal(aliceDBXeNFTPow
            .add(bobDBXeNFTPow)
            .add(carolDBXeNFTPow)
            .add(newRewardPow)
            .add(await dbXeNFTFactory.summedCycleStakes(0)))
    })

    it("Stake during an inactive cycle counts towards next active cycle", async function() {
        await xenft.bulkClaimRank(32, 30)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(41, 15)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})

        await xenftBob.bulkClaimRank(87, 50)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("11"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("2"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const totalEntryPow = await dbXeNFTFactory.totalPowerPerCycle(0)
        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)

        const deployerEntryPow = await dbXeNFTFactory.tokenEntryPower(0)
        await dbXeNFTFactory.claimFees(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(0)).to.equal(deployerEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const aliceEntryPow = await dbXeNFTFactory.tokenEntryPower(1)
        await dbXeNFTFactoryAlice.claimFees(1)
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceBasePow).to.equal(aliceEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))
        
        const bobEntryPow = await dbXeNFTFactory.tokenEntryPower(2)
        await dbXeNFTFactoryBob.claimFees(2)
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobBasePow).to.equal(bobEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactory.burnNFT(10004, {value: ethers.utils.parseEther("1")})

        const ePow21 = ethers.utils.parseEther("1000")
        const aliceDBXeNFTPow = aliceBasePow.mul(ethers.utils.parseEther("11")).div(ePow21)
        const bobDBXeNFTPow = bobBasePow.mul(ethers.utils.parseEther("2")).div(ePow21)
        const newRewardPow = ethers.utils.parseEther("10000").add(ethers.utils.parseEther("10000").div(BigNumber.from("100")))
        expect(await dbXeNFTFactory.summedCycleStakes(2)).to.equal(aliceDBXeNFTPow
            .add(bobDBXeNFTPow)
            .add(newRewardPow)
            .add(await dbXeNFTFactory.summedCycleStakes(0)))
    })

    it("Multiple stakes during the same active cycle", async function() {
        await xenft.bulkClaimRank(128, 1)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(64, 7)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("1000"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("0.3"), 1, {value: ethers.utils.parseEther("1")})

        await xenftBob.bulkClaimRank(100, 100)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("100"), 2, {value: ethers.utils.parseEther("1")})

        await xenftCarol.bulkClaimRank(32, 100)
        await xenftCarol.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryCarol.burnNFT(10004, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther("500"), 3, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther("499"), 3, {value: ethers.utils.parseEther("1")})
        
        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const totalEntryPow = await dbXeNFTFactory.totalPowerPerCycle(0)
        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)

        const deployerEntryPow = await dbXeNFTFactory.tokenEntryPower(0)
        await dbXeNFTFactory.claimFees(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(0)).to.equal(deployerEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const aliceEntryPow = await dbXeNFTFactory.tokenEntryPower(1)
        await dbXeNFTFactoryAlice.claimFees(1)
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceBasePow).to.equal(aliceEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))
        
        const bobEntryPow = await dbXeNFTFactory.tokenEntryPower(2)
        await dbXeNFTFactoryBob.claimFees(2)
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobBasePow).to.equal(bobEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const carolEntryPow = await dbXeNFTFactory.tokenEntryPower(3)
        await dbXeNFTFactoryCarol.claimFees(3)
        const carolBasePow = await dbXeNFTFactory.baseDBXeNFTPower(3)
        expect(carolBasePow).to.equal(carolEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactory.burnNFT(10005, {value: ethers.utils.parseEther("1")})

        const ePow21 = ethers.utils.parseEther("1000")
        const aliceDBXeNFTPow = aliceBasePow.mul(ethers.utils.parseEther("1000.3")).div(ePow21)
        const bobDBXeNFTPow = bobBasePow.mul(ethers.utils.parseEther("100")).div(ePow21)
        const carolDBXeNFTPow = carolBasePow.mul(ethers.utils.parseEther("999")).div(ePow21)
        const newRewardPow = ethers.utils.parseEther("10000").add(ethers.utils.parseEther("10000").div(BigNumber.from("100")))
        expect(await dbXeNFTFactory.summedCycleStakes(1)).to.equal(aliceDBXeNFTPow
            .add(bobDBXeNFTPow)
            .add(carolDBXeNFTPow)
            .add(newRewardPow)
            .add(await dbXeNFTFactory.summedCycleStakes(0)))
    })

    it("Multiple stakes during the same inactive cycle", async function() {
        await xenft.bulkClaimRank(32, 30)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(1, 1)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})

        await xenftBob.bulkClaimRank(87, 50)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("11"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("88"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("2"), 2, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("2"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const totalEntryPow = await dbXeNFTFactory.totalPowerPerCycle(0)
        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)

        const deployerEntryPow = await dbXeNFTFactory.tokenEntryPower(0)
        await dbXeNFTFactory.claimFees(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(0)).to.equal(deployerEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const aliceEntryPow = await dbXeNFTFactory.tokenEntryPower(1)
        await dbXeNFTFactoryAlice.claimFees(1)
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceBasePow).to.equal(aliceEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))
        
        const bobEntryPow = await dbXeNFTFactory.tokenEntryPower(2)
        await dbXeNFTFactoryBob.claimFees(2)
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobBasePow).to.equal(bobEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactory.burnNFT(10004, {value: ethers.utils.parseEther("1")})

        const ePow21 = ethers.utils.parseEther("1000")
        const aliceDBXeNFTPow = aliceBasePow.mul(ethers.utils.parseEther("99")).div(ePow21)
        const bobDBXeNFTPow = bobBasePow.mul(ethers.utils.parseEther("4")).div(ePow21)
        const newRewardPow = ethers.utils.parseEther("10000").add(ethers.utils.parseEther("10000").div(BigNumber.from("100")))
        expect(await dbXeNFTFactory.summedCycleStakes(2)).to.equal(aliceDBXeNFTPow
            .add(bobDBXeNFTPow)
            .add(newRewardPow)
            .add(await dbXeNFTFactory.summedCycleStakes(0)))
    })

    it("Stake during two consecutive active cycle", async function() {
        await xenft.bulkClaimRank(25, 14)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(5, 5)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})

        await xenftBob.bulkClaimRank(11, 13)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("144"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("789"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactory.burnNFT(10004, {value: ethers.utils.parseEther("1")})

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("441"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("987"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const totalEntryPow = await dbXeNFTFactory.totalPowerPerCycle(0)
        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)

        const deployerEntryPow = await dbXeNFTFactory.tokenEntryPower(0)
        await dbXeNFTFactory.claimFees(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(0)).to.equal(deployerEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const aliceEntryPow = await dbXeNFTFactory.tokenEntryPower(1)
        await dbXeNFTFactoryAlice.claimFees(1)
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceBasePow).to.equal(aliceEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))
        
        const bobEntryPow = await dbXeNFTFactory.tokenEntryPower(2)
        await dbXeNFTFactoryBob.claimFees(2)
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobBasePow).to.equal(bobEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactory.burnNFT(10005, {value: ethers.utils.parseEther("1")})

        const ePow21 = ethers.utils.parseEther("1000")
        const aliceDBXeNFTPow = aliceBasePow.mul(ethers.utils.parseEther("585")).div(ePow21)
        const bobDBXeNFTPow = bobBasePow.mul(ethers.utils.parseEther("1776")).div(ePow21)
        const newRewardPow = ethers.utils.parseEther("10000").add(ethers.utils.parseEther("10000").div(BigNumber.from("100")))
        const lastCycleRewardPow = newRewardPow.add(newRewardPow.div(BigNumber.from("100")))
        expect(await dbXeNFTFactory.summedCycleStakes(2)).to.equal(aliceDBXeNFTPow
            .add(bobDBXeNFTPow)
            .add(lastCycleRewardPow)
            .add(newRewardPow)
            .add(await dbXeNFTFactory.summedCycleStakes(0)))
    })
    
    it("Stake during two consecutive inactive cycle", async function() {
        await xenft.bulkClaimRank(32, 30)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(1, 1)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})

        await xenftBob.bulkClaimRank(87, 50)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("11"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("2"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("88"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("2"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const totalEntryPow = await dbXeNFTFactory.totalPowerPerCycle(0)
        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)

        const deployerEntryPow = await dbXeNFTFactory.tokenEntryPower(0)
        await dbXeNFTFactory.claimFees(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(0)).to.equal(deployerEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const aliceEntryPow = await dbXeNFTFactory.tokenEntryPower(1)
        await dbXeNFTFactoryAlice.claimFees(1)
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceBasePow).to.equal(aliceEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))
        
        const bobEntryPow = await dbXeNFTFactory.tokenEntryPower(2)
        await dbXeNFTFactoryBob.claimFees(2)
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobBasePow).to.equal(bobEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactory.burnNFT(10004, {value: ethers.utils.parseEther("1")})

        const ePow21 = ethers.utils.parseEther("1000")
        const aliceDBXeNFTPow = aliceBasePow.mul(ethers.utils.parseEther("99")).div(ePow21)
        const bobDBXeNFTPow = bobBasePow.mul(ethers.utils.parseEther("4")).div(ePow21)
        const newRewardPow = ethers.utils.parseEther("10000").add(ethers.utils.parseEther("10000").div(BigNumber.from("100")))
        expect(await dbXeNFTFactory.summedCycleStakes(3)).to.equal(aliceDBXeNFTPow
            .add(bobDBXeNFTPow)
            .add(newRewardPow)
            .add(await dbXeNFTFactory.summedCycleStakes(0)))
    })

    it("Stake consecutively during active cycle then inactive cycle", async function() {
        await xenft.bulkClaimRank(77, 30)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(1, 100)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})

        await xenftBob.bulkClaimRank(44, 45)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("4"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("11"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("88"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("2"), 2, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("2"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const totalEntryPow = await dbXeNFTFactory.totalPowerPerCycle(0)
        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)

        const deployerEntryPow = await dbXeNFTFactory.tokenEntryPower(0)
        await dbXeNFTFactory.claimFees(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(0)).to.equal(deployerEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        const aliceEntryPow = await dbXeNFTFactory.tokenEntryPower(1)
        await dbXeNFTFactoryAlice.claimFees(1)
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceBasePow).to.equal(aliceEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))
        
        const bobEntryPow = await dbXeNFTFactory.tokenEntryPower(2)
        await dbXeNFTFactoryBob.claimFees(2)
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobBasePow).to.equal(bobEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactory.burnNFT(10004, {value: ethers.utils.parseEther("1")})

        const ePow21 = ethers.utils.parseEther("1000")
        const aliceDBXeNFTPow = aliceBasePow.mul(ethers.utils.parseEther("99")).div(ePow21)
        const bobDBXeNFTPow = bobBasePow.mul(ethers.utils.parseEther("8")).div(ePow21)
        const newRewardPow = ethers.utils.parseEther("10000").add(ethers.utils.parseEther("10000").div(BigNumber.from("100")))
        expect(await dbXeNFTFactory.summedCycleStakes(2)).to.equal(aliceDBXeNFTPow
            .add(bobDBXeNFTPow)
            .add(newRewardPow)
            .add(await dbXeNFTFactory.summedCycleStakes(0)))
    })

    it.only("Stake consecutively during inactive cycle then active cycle", async function() {
        await xenft.bulkClaimRank(7, 8)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(97, 3)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})

        await xenftBob.bulkClaimRank(14, 29)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("441"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("987"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactory.burnNFT(10004, {value: ethers.utils.parseEther("1")})

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("144"), 1, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("789"), 2, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.bulkClaimRank(2, 2)
        await xenft.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactory.burnNFT(10005, {value: ethers.utils.parseEther("1")})

        const totalEntryPow = await dbXeNFTFactory.totalPowerPerCycle(0)
        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)

        const deployerEntryPow = await dbXeNFTFactory.tokenEntryPower(0)
        await dbXeNFTFactory.claimFees(0)
        expect(await dbXeNFTFactory.baseDBXeNFTPower(0)).to.equal(deployerEntryPow.mul(firstCycleRewardPow).div(totalEntryPow))

        await dbXeNFTFactoryAlice.claimFees(1)
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
    
        await dbXeNFTFactoryBob.claimFees(2)
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)

        const ePow21 = ethers.utils.parseEther("1000")
        const aliceDBXeNFTPow = aliceBasePow.mul(ethers.utils.parseEther("585")).div(ePow21)
        const bobDBXeNFTPow = bobBasePow.mul(ethers.utils.parseEther("1776")).div(ePow21)
        const newRewardPow = ethers.utils.parseEther("10000").add(ethers.utils.parseEther("10000").div(BigNumber.from("100")))
        const lastCycleRewardPow = newRewardPow.add(newRewardPow.div(BigNumber.from("100")))
        expect(await dbXeNFTFactory.summedCycleStakes(3)).to.equal(aliceDBXeNFTPow
            .add(bobDBXeNFTPow)
            .add(lastCycleRewardPow)
            .add(newRewardPow)
            .add(await dbXeNFTFactory.summedCycleStakes(0)))
    })
})