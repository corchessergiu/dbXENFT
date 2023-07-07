const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test fee claiming functionality", async function() {
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

    it("Basic fee claiming for entry cycle", async function() {
        await xenft.bulkClaimRank(128, 1)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(64, 7)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})
        

        await xenftBob.bulkClaimRank(100, 100)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})

        await xenftCarol.bulkClaimRank(32, 100)
        await xenftCarol.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryCarol.burnNFT(10004, {value: ethers.utils.parseEther("1")})
        
        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)
        const firstCycleAccruedFees =  await dbXeNFTFactory.cycleAccruedFees(0)

        const deployerTx = await dbXeNFTFactory.claimFees(0)
        const deployerReceipt = await deployerTx.wait()
        const deployerFeesClaimedEvent = deployerReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const deployerFeesClaimed = deployerFeesClaimedEvent.args.fees
        const deployerBasePow = await dbXeNFTFactory.baseDBXeNFTPower(0)
        expect(deployerFeesClaimed).to.equal(deployerBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        const aliceTx = await dbXeNFTFactoryAlice.claimFees(1)
        const aliceReceipt = await aliceTx.wait()
        const aliceFeesClaimedEvent = aliceReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const aliceFeesClaimed = aliceFeesClaimedEvent.args.fees
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceFeesClaimed).to.equal(aliceBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        const bobTx = await dbXeNFTFactoryBob.claimFees(2)
        const bobReceipt = await bobTx.wait()
        const bobFeesClaimedEvent = bobReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const bobClaimedFees = bobFeesClaimedEvent.args.fees
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobClaimedFees).to.equal(bobBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        const carolTx = await dbXeNFTFactoryCarol.claimFees(3)
        const carolReceipt = await carolTx.wait()
        const carolFeesClaimedEvent = carolReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const carolFeesClaimed = carolFeesClaimedEvent.args.fees
        const carolBasePow = await dbXeNFTFactory.baseDBXeNFTPower(3)
        expect(carolFeesClaimed).to.equal(carolBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        expect(firstCycleAccruedFees).to.equal(deployerFeesClaimed
            .add(aliceFeesClaimed)
            .add(bobClaimedFees)
            .add(carolFeesClaimed)
        )
    })

    it("Only fees claimed starting the next cycle after stake will be impacted by extra stake power", async function(){
        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       

        await xenftAlice.bulkClaimRank(1, 1)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("1000"), 1, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)
        const firstCycleAccruedFees =  await dbXeNFTFactory.cycleAccruedFees(0)

        let deployerTx = await dbXeNFTFactory.claimFees(0)
        let deployerReceipt = await deployerTx.wait()
        let deployerFeesClaimedEvent = deployerReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        let deployerFeesClaimed = deployerFeesClaimedEvent.args.fees
        let deployerBasePow = await dbXeNFTFactory.baseDBXeNFTPower(0)
        expect(deployerFeesClaimed).to.equal(deployerBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        let aliceTx = await dbXeNFTFactoryAlice.claimFees(1)
        let aliceReceipt = await aliceTx.wait()
        let aliceFeesClaimedEvent = aliceReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        let aliceFeesClaimed = aliceFeesClaimedEvent.args.fees
        let aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceFeesClaimed).to.equal(aliceBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))


        expect(deployerFeesClaimed).to.equal(aliceFeesClaimed)

        const totalFeesClaimedFirstCycle = deployerFeesClaimed.add(aliceFeesClaimed)

        await xenftBob.bulkClaimRank(100, 100)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.burnNFT(10003, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const secondCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(1)
        const secondCycleAccruedFees =  await dbXeNFTFactory.cycleAccruedFees(1)

        const bobTx = await dbXeNFTFactoryBob.claimFees(2)
        const bobReceipt = await bobTx.wait()
        const bobFeesClaimedEvent = bobReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const bobClaimedFees = bobFeesClaimedEvent.args.fees
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        const totalPowSecondCycle = firstCycleRewardPow.add(secondCycleRewardPow).add(aliceBasePow)

        expect(bobClaimedFees).to.equal(bobBasePow.mul(secondCycleAccruedFees)
        .div(totalPowSecondCycle))

        deployerTx = await dbXeNFTFactory.claimFees(0)
        deployerReceipt = await deployerTx.wait()
        deployerFeesClaimedEvent = deployerReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        deployerFeesClaimed = deployerFeesClaimedEvent.args.fees
        expect(deployerFeesClaimed).to.equal(deployerBasePow.mul(secondCycleAccruedFees).div(totalPowSecondCycle))

        aliceTx = await dbXeNFTFactoryAlice.claimFees(1)
        aliceReceipt = await aliceTx.wait()
        aliceFeesClaimedEvent = aliceReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        aliceFeesClaimed = aliceFeesClaimedEvent.args.fees
        aliceDBXeNFTPow = await dbXeNFTFactory.DBXeNFTPower(1)
        expect(aliceFeesClaimed).to.equal(aliceDBXeNFTPow.mul(secondCycleAccruedFees).div(totalPowSecondCycle))


        expect(deployerFeesClaimed).to.not.equal(aliceFeesClaimed)
        expect(firstCycleAccruedFees.add(secondCycleAccruedFees)).to.equal(
            totalFeesClaimedFirstCycle.add(bobClaimedFees).add(deployerFeesClaimed)
        .add(aliceFeesClaimed))
    })

    it.only("Staking in entry cycle results in correct fees calculation", async function(){
        await xenft.bulkClaimRank(20, 10)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.burnNFT(10001, {value: ethers.utils.parseEther("1")})
       
        await xenftAlice.bulkClaimRank(10, 20)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.burnNFT(10002, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("5000"), 1, {value: ethers.utils.parseEther("5")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.bulkClaimRank(45, 88)
        await xenft.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactory.burnNFT(10003, {value: ethers.utils.parseEther("1")})

        await xenftBob.bulkClaimRank(60, 90)
        await xenftBob.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryBob.burnNFT(10004, {value: ethers.utils.parseEther("1")})
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("11"), 3, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.bulkClaimRank(100, 100)
        await xenft.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactory.burnNFT(10005, {value: ethers.utils.parseEther("1")})

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.bulkClaimRank(1, 1)
        await xenft.approve(dbXeNFTFactory.address, 10006)
        await dbXeNFTFactory.burnNFT(10006, {value: ethers.utils.parseEther("1")})

        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)
        const firstCycleAccruedFees =  await dbXeNFTFactory.cycleAccruedFees(0)
        let scalingFactor = await dbXeNFTFactory.SCALING_FACTOR()
        let cfpss3 = await dbXeNFTFactory.cycleFeesPerStakeSummed(3)
        let cfpss2 = await dbXeNFTFactory.cycleFeesPerStakeSummed(2)
        let cfpss1 = await dbXeNFTFactory.cycleFeesPerStakeSummed(1)

        let deployerTx = await dbXeNFTFactory.claimFees(0)
        let deployerReceipt = await deployerTx.wait()
        let deployerFeesClaimedEvent = deployerReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        let deployerFeesClaimed = deployerFeesClaimedEvent.args.fees
        let deployerBasePow = await dbXeNFTFactory.baseDBXeNFTPower(0)
        
        expect(deployerFeesClaimed).to.equal(deployerBasePow.mul(cfpss3).div(scalingFactor))

        deployerTx = await dbXeNFTFactory.claimFees(2)
        deployerReceipt = await deployerTx.wait()
        deployerFeesClaimedEvent = deployerReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        let deployerFeesClaimedSecondNFT = deployerFeesClaimedEvent.args.fees
        deployerBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(deployerFeesClaimedSecondNFT).to.equal(deployerBasePow.mul(cfpss3.sub(cfpss1)).div(scalingFactor))

        let aliceTx = await dbXeNFTFactoryAlice.claimFees(1)
        let aliceReceipt = await aliceTx.wait()
        let aliceFeesClaimedEvent = aliceReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        let aliceFeesClaimed = aliceFeesClaimedEvent.args.fees
        let aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        let aliceDBXeNFTPow = await dbXeNFTFactory.DBXeNFTPower(1)
        let aliceExtraPow = aliceDBXeNFTPow.sub(aliceBasePow)
        let aliceEntryCycleFees = aliceBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow)
        let aliceRestFeesClaimed = aliceDBXeNFTPow.mul(cfpss3.sub(cfpss1)).div(scalingFactor)
        let aliceBasePowFees = aliceBasePow.mul(cfpss3).div(scalingFactor)
        let aliceExtraPowFees = aliceExtraPow.mul(cfpss3.sub(cfpss1)).div(scalingFactor)
        expect(aliceFeesClaimed).to.equal(aliceEntryCycleFees.add(aliceRestFeesClaimed))
        expect(aliceFeesClaimed).to.equal(aliceBasePowFees.add(aliceExtraPowFees))

        const secondCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(1)
        const secondCycleAccruedFees =  await dbXeNFTFactory.cycleAccruedFees(1)

        const bobTx = await dbXeNFTFactoryBob.claimFees(3)
        const bobReceipt = await bobTx.wait()
        const bobFeesClaimedEvent = bobReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const bobClaimedFees = bobFeesClaimedEvent.args.fees
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(3)
        let bobDBXeNFTPow = await dbXeNFTFactory.DBXeNFTPower(3)
        let bobExtraPow = bobDBXeNFTPow.sub(bobBasePow)
        let bobEntryCycleFees = bobBasePow.mul(secondCycleAccruedFees).
            div(firstCycleRewardPow.add(secondCycleRewardPow).add(aliceExtraPow))
        let bobRestFeesClaimed = bobDBXeNFTPow.mul(cfpss3.sub(cfpss2)).div(scalingFactor)
        let bobBasePowFees = bobBasePow.mul(cfpss3.sub(cfpss1)).div(scalingFactor)
        let bobExtraPowFees = bobExtraPow.mul(cfpss3.sub(cfpss2)).div(scalingFactor)
        //expect(bobClaimedFees).to.equal(bobEntryCycleFees.add(bobRestFeesClaimed))
        expect(bobClaimedFees).to.equal(bobBasePowFees.add(bobExtraPowFees))

        const thirdCycleAccruedFees = await dbXeNFTFactory.cycleAccruedFees(2)

        expect(firstCycleAccruedFees.add(secondCycleAccruedFees).add(thirdCycleAccruedFees))
            .to.equal(deployerFeesClaimed.add(deployerFeesClaimedSecondNFT)
            .add(aliceFeesClaimed).add(bobClaimedFees))
    })
})  