const { expect } = require("chai");
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

        await DBX.connect(deployer).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(alice).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(bob).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(carol).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
        await DBX.connect(dean).approve(dbXeNFTFactory.address, ethers.utils.parseEther("10000"))
    });

    it("Test fee with console.log on smart contract!", async function() {
        await xenft.bulkClaimRank(128, 71)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })

        console.log("**************************************************");

        await xenft.bulkClaimRank(128, 10)
        await xenft.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactory.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 11 * 24]);
        await hre.ethers.provider.send("evm_mine");

        console.log("**************************************************");

        await xenft.bulkClaimRank(128, 10)

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 11 * 24]);
        await hre.ethers.provider.send("evm_mine");

        await xenft.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactory.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })
    })

    it("Test fee with multiple accounts!", async function() {
        await xenftAlice.bulkClaimRank(128, 71)
        await xenftAlice.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactoryAlice.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })

        console.log("**************************************************");

        await xenftBob.bulkClaimRank(128, 10)
        await xenftBob.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryBob.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24]);
        await hre.ethers.provider.send("evm_mine");

        console.log("**************************************************");

        await xenftDean.bulkClaimRank(128, 10)

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24]);
        await hre.ethers.provider.send("evm_mine");

        await xenftDean.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryDean.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })
    })

    it("Test fee with multiple accounts and gap cycles!", async function() {
        await xenft.bulkClaimRank(128, 71)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })

        console.log("**************************************************");

        await xenftAlice.bulkClaimRank(128, 10)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })

        await xenftBob.bulkClaimRank(128, 10)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })

        await xenftDean.bulkClaimRank(128, 10)
        await xenftDean.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryDean.mintDBXENFT(10004, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 11 * 24]);
        await hre.ethers.provider.send("evm_mine");

        console.log("**************************************************");

        await xenftCarol.bulkClaimRank(128, 10)
        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 11 * 24]);
        await hre.ethers.provider.send("evm_mine");

        await xenftCarol.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactoryCarol.mintDBXENFT(10005, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 11 * 24]);
        await hre.ethers.provider.send("evm_mine");

        await xenftBob.bulkClaimRank(128, 31)
        await xenftBob.approve(dbXeNFTFactory.address, 10006)
        await dbXeNFTFactoryBob.mintDBXENFT(10006, { value: ethers.utils.parseEther("1") })

        await xenftDean.bulkClaimRank(128, 31)
        await xenftDean.approve(dbXeNFTFactory.address, 10007)
        await dbXeNFTFactoryDean.mintDBXENFT(10007, { value: ethers.utils.parseEther("1") })

        await xenftAlice.bulkClaimRank(128, 31)
        await xenftAlice.approve(dbXeNFTFactory.address, 10008)
        await dbXeNFTFactoryAlice.mintDBXENFT(10008, { value: ethers.utils.parseEther("1") })
    })

    it.only("Test protocol fee for NFT with burn amount!", async function() {
        await XENContract.approve(xenft.address, ethers.utils.parseEther("100000000000000000"))
        await xenft.bulkClaimRank(128, 1);
        await xenft.bulkClaimRank(128, 1);
        await xenft.bulkClaimRank(128, 1);
        await xenft.bulkClaimRank(128, 1);
        await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("250000000"));
        await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("500000000"));
        await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("1000000000"));
        await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("2000000000"));
        await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("2500000000"));
        await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("5000000000"));
        await xenft.bulkClaimRankLimited(100, 1, ethers.utils.parseEther("10000000000"));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.approve(dbXeNFTFactory.address, 10001);
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("11") });

        await xenft.approve(dbXeNFTFactory.address, 10002);
        await dbXeNFTFactory.mintDBXENFT(10002, { value: ethers.utils.parseEther("11") });
        console.log("*************");

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenft.approve(dbXeNFTFactory.address, 10003);
        await dbXeNFTFactory.mintDBXENFT(10003, { value: ethers.utils.parseEther("11") });
        console.log("*************");
        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        console.log("*************");
        await xenft.approve(dbXeNFTFactory.address, 10004);
        await dbXeNFTFactory.mintDBXENFT(10004, { value: ethers.utils.parseEther("11") });
        console.log("*************");
        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")
        console.log("*************");
        console.log("*************");
        await xenft.approve(dbXeNFTFactory.address, 6001);
        await dbXeNFTFactory.mintDBXENFT(6001, { value: ethers.utils.parseEther("11") });
        console.log("*************");
        console.log("*************");
        await xenft.approve(dbXeNFTFactory.address, 3001);
        await dbXeNFTFactory.mintDBXENFT(3001, { value: ethers.utils.parseEther("11") });
        console.log("*************");
        console.log("*************");
        await xenft.approve(dbXeNFTFactory.address, 1001);
        await dbXeNFTFactory.mintDBXENFT(1001, { value: ethers.utils.parseEther("11") });
        console.log("*************");
        console.log("*************");
        await xenft.approve(dbXeNFTFactory.address, 1002);
        await dbXeNFTFactory.mintDBXENFT(1002, { value: ethers.utils.parseEther("11") });
        console.log("*************");
        console.log("*************");
        await xenft.approve(dbXeNFTFactory.address, 101);
        await dbXeNFTFactory.mintDBXENFT(101, { value: ethers.utils.parseEther("11") });
        console.log("*************");
        console.log("*************");
        await xenft.approve(dbXeNFTFactory.address, 1);
        await dbXeNFTFactory.mintDBXENFT(1, { value: ethers.utils.parseEther("11") });
    })

})