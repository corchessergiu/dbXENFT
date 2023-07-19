const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test unstake functionality", async function() {
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

    it("Basic unstake case", async function() {
        await xenft.bulkClaimRank(13, 37)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })
        await dbXeNFTFactory.stake(ethers.utils.parseEther("2"), 0, { value: ethers.utils.parseEther("5") })

        await xenftAlice.bulkClaimRank(49, 77)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("233"), 1, { value: ethers.utils.parseEther("5") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenftBob.bulkClaimRank(41, 2)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("21"), 2, { value: ethers.utils.parseEther("5") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await dbXeNFTFactory.stake(ethers.utils.parseEther("1"), 0, { value: ethers.utils.parseEther("5") })
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("1"), 1, { value: ethers.utils.parseEther("5") })

        let withdrawableToken0 = await dbXeNFTFactory.tokenWithdrawableStake(0);
        let withdrawableToken1 = await dbXeNFTFactory.tokenWithdrawableStake(1);
        expect(withdrawableToken0).to.equal(ethers.utils.parseEther("2"));
        expect(withdrawableToken1).to.equal(ethers.utils.parseEther("233"));

        let aliceBalanceBeforeFirstUnstake = await ethers.provider.getBalance(alice.address);
        await dbXeNFTFactoryAlice.unstake(1, ethers.utils.parseEther("22222"));
        let aliceBalanceBeforeAfterFirstUnstake = await ethers.provider.getBalance(alice.address);

        console.log(aliceBalanceBeforeFirstUnstake);
        console.log(aliceBalanceBeforeAfterFirstUnstake);

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")
            // await dbXeNFTFactoryAlice.unstake(1, ethers.utils.parseEther("233"))
            // expect(await dbXeNFTFactory.summedCycleStakes(2)).to.equal(
            //     (await dbXeNFTFactory.rewardPerCycle(0))
            //     .add(await dbXeNFTFactory.rewardPerCycle(1))
            //     .add(await dbXeNFTFactory.rewardPerCycle(2))
            // )

        // await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        // await hre.ethers.provider.send("evm_mine")

        // await xenft.bulkClaimRank(1, 1)
        // await xenft.approve(dbXeNFTFactory.address, 10005)
        // await dbXeNFTFactory.mintDBXENFT(10005, { value: ethers.utils.parseEther("1") })

        // expect(await dbXeNFTFactory.tokenWithdrawableStake(1)).to.equal(0)

    })
})