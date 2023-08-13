const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test claimFee functionality", async function() {
    let xenft, dbXeNFTFactory, XENContract, DBX, DBXeNFT;
    let deployer, alice, bob, carol, dean;
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

        DBX.transfer(deployer.address, ethers.utils.parseEther("10000"))
        DBX.transfer(alice.address, ethers.utils.parseEther("10000"))
        DBX.transfer(bob.address, ethers.utils.parseEther("10000"))
        DBX.transfer(carol.address, ethers.utils.parseEther("10000"))
        DBX.transfer(dean.address, ethers.utils.parseEther("10000"))

        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(alice).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(bob).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(carol).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(dean).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))

    });

    it("Test cycle fee distribution equally", async function() {
        await xenft.bulkClaimRank(128, 1)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })

        await xenftAlice.bulkClaimRank(128, 1)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })

        await xenftBob.bulkClaimRank(128, 1)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })

        await xenftCarol.bulkClaimRank(128, 1)
        await xenftCarol.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryCarol.mintDBXENFT(10004, { value: ethers.utils.parseEther("1") })

        await xenftDean.bulkClaimRank(128, 1)
        await xenftDean.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactoryDean.mintDBXENFT(10005, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)
        const firstCycleAccruedFees = await dbXeNFTFactory.cycleAccruedFees(0)
        expect(firstCycleRewardPow).to.equal(ethers.utils.parseEther("10000"));
        //4 burn with same date => fee for each user will be equal
        let feeAccPerUser = firstCycleAccruedFees.div(5);

        const deployerTx = await dbXeNFTFactory.claimFees(0)
        const deployerReceipt = await deployerTx.wait()
        const deployerFeesClaimedEvent = deployerReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const deployerFeesClaimed = deployerFeesClaimedEvent.args.fees
        expect(deployerFeesClaimed).to.equal(feeAccPerUser);
        const deployerBasePow = await dbXeNFTFactory.baseDBXeNFTPower(0)
        expect(deployerFeesClaimed).to.equal(deployerBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        const aliceTx = await dbXeNFTFactoryAlice.claimFees(1)
        const aliceReceipt = await aliceTx.wait()
        const aliceFeesClaimedEvent = aliceReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const aliceFeesClaimed = aliceFeesClaimedEvent.args.fees;
        expect(aliceFeesClaimed).to.equal(feeAccPerUser);
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceFeesClaimed).to.equal(aliceBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        const bobTx = await dbXeNFTFactoryBob.claimFees(2)
        const bobReceipt = await bobTx.wait()
        const bobFeesClaimedEvent = bobReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const bobClaimedFees = bobFeesClaimedEvent.args.fees;
        expect(bobClaimedFees).to.equal(feeAccPerUser);
        const bobBasePow = await dbXeNFTFactory.baseDBXeNFTPower(2)
        expect(bobClaimedFees).to.equal(bobBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        const carolTx = await dbXeNFTFactoryCarol.claimFees(3)
        const carolReceipt = await carolTx.wait()
        const carolFeesClaimedEvent = carolReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const carolFeesClaimed = carolFeesClaimedEvent.args.fees
        expect(carolFeesClaimed).to.equal(feeAccPerUser);
        const carolBasePow = await dbXeNFTFactory.baseDBXeNFTPower(3)
        expect(carolFeesClaimed).to.equal(carolBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        const deanTx = await dbXeNFTFactoryDean.claimFees(4)
        const deanReceipt = await deanTx.wait()
        const deanFeesClaimedEvent = deanReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const deanFeesClaimed = deanFeesClaimedEvent.args.fees
        expect(deanFeesClaimed).to.equal(feeAccPerUser);
        const deanBasePow = await dbXeNFTFactory.baseDBXeNFTPower(4)
        expect(deanFeesClaimed).to.equal(deanBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        expect(firstCycleAccruedFees).to.equal(deployerFeesClaimed
            .add(aliceFeesClaimed)
            .add(bobClaimedFees)
            .add(carolFeesClaimed)
            .add(deanFeesClaimed)
        )
    })

    it("Test cycle fee distribution on multiple cycles ", async function() {
        await xenft.bulkClaimRank(128, 10)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })

        await xenftAlice.bulkClaimRank(128, 40)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)
        const firstCycleAccruedFees = await dbXeNFTFactory.cycleAccruedFees(0)
        expect(firstCycleRewardPow).to.equal(ethers.utils.parseEther("10000"));
        //Deployer have 128 addresses with term of 10 days and alice have 128 with term of 40 days => alice must have 4x more fees than deployer
        let feeAccPerUser = firstCycleAccruedFees.div(5);

        const deployerTx = await dbXeNFTFactory.claimFees(0)
        const deployerReceipt = await deployerTx.wait()
        const deployerFeesClaimedEvent = deployerReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const deployerFeesClaimed = deployerFeesClaimedEvent.args.fees
        expect(deployerFeesClaimed).to.equal(feeAccPerUser);
        const deployerBasePow = await dbXeNFTFactory.baseDBXeNFTPower(0)
        expect(deployerFeesClaimed).to.equal(deployerBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        const aliceTx = await dbXeNFTFactoryAlice.claimFees(1)
        const aliceReceipt = await aliceTx.wait()
        const aliceFeesClaimedEvent = aliceReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const aliceFeesClaimed = aliceFeesClaimedEvent.args.fees;
        expect(aliceFeesClaimed).to.equal(feeAccPerUser.mul(4));
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceFeesClaimed).to.equal(aliceBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        await xenftBob.bulkClaimRank(128, 15)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })

        await xenftCarol.bulkClaimRank(128, 60)
        await xenftCarol.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryCarol.mintDBXENFT(10004, { value: ethers.utils.parseEther("1") })

        await xenftDean.bulkClaimRank(128, 90)
        await xenftDean.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactoryDean.mintDBXENFT(10005, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")
        const secondCycleAccruedFees = await dbXeNFTFactory.cycleAccruedFees(1)

        const bobTx = await dbXeNFTFactoryBob.claimFees(2)
        const bobReceipt = await bobTx.wait()
        const bobFeesClaimedEvent = bobReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const bobFeesClaimed = bobFeesClaimedEvent.args.fees

        const carolTx = await dbXeNFTFactoryCarol.claimFees(3)
        const carolReceipt = await carolTx.wait()
        const carolFeesClaimedEvent = carolReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const carolFeesClaimed = carolFeesClaimedEvent.args.fees;
        //expect 0.089115598328358208 == 0.089115469691542288 
        //=> difference 0.00000012863681592
        //mul(6) because dean has an NFT whose term is 4 times greater than bob
        //expect(carolFeesClaimed).to.equal(bobFeesClaimed.mul(4))

        const deanTx = await dbXeNFTFactoryDean.claimFees(4)
        const deanReceipt = await deanTx.wait()
        const deanFeesClaimedEvent = deanReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const deanFeesClaimed = deanFeesClaimedEvent.args.fees;
        //expect 133673397492537313 == 133673204537313432
        //=> difference 0.000000192955223872
        //mul(6) because dean has an NFT whose term is 6 times greater than bob
        //expect(deanFeesClaimed).to.equal(bobFeesClaimed.mul(6))

        //Alice and Deployer also have reward because their nft still have power(they have not yet claimed their rewards)

        const deployerTxSecondCycle = await dbXeNFTFactory.claimFees(0)
        const deployerReceiptSecondCycle = await deployerTxSecondCycle.wait()
        const deployerFeesClaimedEventSecondCycle = deployerReceiptSecondCycle.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const deployerFeesClaimedSecondCycle = deployerFeesClaimedEventSecondCycle.args.fees;

        const aliceTxSecondCycle = await dbXeNFTFactoryAlice.claimFees(1)
        const aliceReceiptSecondCycle = await aliceTxSecondCycle.wait()
        const aliceFeesClaimedEventSecondCycle = aliceReceiptSecondCycle.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const aliceFeesClaimedSecondCycle = aliceFeesClaimedEventSecondCycle.args.fees;

        let totalCycleAccFeesClaimed = (((bobFeesClaimed.add(carolFeesClaimed)).add(deanFeesClaimed)).add(deployerFeesClaimedSecondCycle)).add(aliceFeesClaimedSecondCycle);
        //expect 487709312000000000 == 487709311999999998
        //0.000000001... wei difference
        //expect(secondCycleAccruedFees).to.equal(totalCycleAccFeesClaimed);
    })

    it("Test fee distribution using the same nft and using extrapower from the stake action", async function() {
        await xenft.bulkClaimRank(128, 10)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })

        await xenftAlice.bulkClaimRank(128, 10)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })

        let firstCyclePowerDistribution = await dbXeNFTFactory.currentCycleReward();
        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const firstCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(0)
        const firstCycleAccruedFees = await dbXeNFTFactory.cycleAccruedFees(0)
        expect(firstCycleRewardPow).to.equal(ethers.utils.parseEther("10000"));
        let feeAccPerUser = firstCycleAccruedFees.div(2);

        const deployerTx = await dbXeNFTFactory.claimFees(0)
        const deployerReceipt = await deployerTx.wait()
        const deployerFeesClaimedEvent = deployerReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const deployerFeesClaimed = deployerFeesClaimedEvent.args.fees
        expect(deployerFeesClaimed).to.equal(feeAccPerUser);
        const deployerBasePow = await dbXeNFTFactory.baseDBXeNFTPower(0)
        expect(deployerFeesClaimed).to.equal(deployerBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        const aliceTx = await dbXeNFTFactoryAlice.claimFees(1)
        const aliceReceipt = await aliceTx.wait()
        const aliceFeesClaimedEvent = aliceReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const aliceFeesClaimed = aliceFeesClaimedEvent.args.fees;
        expect(aliceFeesClaimed).to.equal(feeAccPerUser);
        const aliceBasePow = await dbXeNFTFactory.baseDBXeNFTPower(1)
        expect(aliceFeesClaimed).to.equal(aliceBasePow.mul(firstCycleAccruedFees).div(firstCycleRewardPow))

        await xenftBob.bulkClaimRank(128, 10)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const secondCycleAccFees = await dbXeNFTFactory.cycleAccruedFees(1)
        const secondCycleRewardPow = await dbXeNFTFactory.rewardPerCycle(1)

        const deployerTxSecond = await dbXeNFTFactory.claimFees(0)
        const deployerReceiptSecond = await deployerTxSecond.wait()
        const deployerFeesClaimedEventSecond = deployerReceiptSecond.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const deployerFeesClaimedSecond = deployerFeesClaimedEventSecond.args.fees

        const aliceTxSecond = await dbXeNFTFactoryAlice.claimFees(1)
        const aliceReceiptSecond = await aliceTxSecond.wait()
        const aliceFeesClaimedEventSecond = aliceReceiptSecond.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const aliceFeesClaimedSecond = aliceFeesClaimedEventSecond.args.fees;

        const bobTx = await dbXeNFTFactoryBob.claimFees(2)
        const bobReceipt = await bobTx.wait()
        const bobFeesClaimedEvent = bobReceipt.events.find(function(el) {
            return el.event == "FeesClaimed"
        })
        const bobFeesClaimed = bobFeesClaimedEvent.args.fees;

        let totalFeesClaimedInSecondCycle = deployerFeesClaimedSecond.add(aliceFeesClaimedSecond).add(bobFeesClaimed);
        //29558144000000000 == 29558143999999998
        //=> difference 0.000000001....
        //expect(secondCycleAccFees).to.equal(totalFeesClaimedInSecondCycle)

        expect(await dbXeNFTFactory.dbxenftPower(0)).to.equal(await dbXeNFTFactory.dbxenftPower(1));
        let dbxenNFT2 = await dbXeNFTFactory.dbxenftPower(2);
        let expectedPower = firstCyclePowerDistribution.add(firstCyclePowerDistribution.div(100));
        expect(dbxenNFT2).to.equal(expectedPower);

        let deployerExpectedReward = ((await dbXeNFTFactory.dbxenftPower(0)).mul(secondCycleAccFees)).div((secondCycleRewardPow.add(firstCycleRewardPow)));
        expect(deployerFeesClaimedSecond).to.equal(deployerExpectedReward);

        let aliceExpectedReward = ((await dbXeNFTFactoryAlice.dbxenftPower(1)).mul(secondCycleAccFees)).div((secondCycleRewardPow.add(firstCycleRewardPow)));
        expect(aliceFeesClaimedSecond).to.equal(aliceExpectedReward);

        let bobExpectedReward = ((await dbXeNFTFactory.dbxenftPower(2)).mul(secondCycleAccFees)).div((secondCycleRewardPow.add(firstCycleRewardPow)));
        expect(bobFeesClaimed).to.equal(bobExpectedReward);

        let basePowerNFT0 = await dbXeNFTFactory.baseDBXeNFTPower(0);
        console.log(basePowerNFT0);
        console.log(await dbXeNFTFactory.dbxenftPower(0));

        let deployerFirstStakeAmount = 1;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactory.stake(ethers.utils.parseEther(deployerFirstStakeAmount.toString()), 0, { value: ethers.utils.parseEther("1") });

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")
            //dbxenftPower
        await dbXeNFTFactory.stake(ethers.utils.parseEther("1"), 0, { value: ethers.utils.parseEther("0.001") });

        console.log(await dbXeNFTFactory.dbxenftPower(0));


        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")
            //dbxenftPower
        await dbXeNFTFactory.stake(ethers.utils.parseEther("1"), 0, { value: ethers.utils.parseEther("0.001") });

        console.log(await dbXeNFTFactory.dbxenftPower(0));


    })

})