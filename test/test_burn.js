const { expect } = require("chai");
const exp = require("constants");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe.only("Test burn functionality", async function() {
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

        DBXENFT = await dbXENFT.deploy(xenft.address, XENContract.address, ethers.constants.AddressZero, ethers.constants.AddressZero);
        await DBXENFT.deployed();
    });

    it("Simple burn before claimable period", async() => {
        await XENContract.approve(xenft.address, ethers.utils.parseEther("100000000000000000"))
        await xenft.bulkClaimRank(128, 1);

        const MintInfo = await ethers.getContractFactory("MintInfo", deployer)
        const mintinfo = await MintInfo.deploy()
        await mintinfo.deployed()

        const dbXENFTLocal = await ethers.getContractFactory("dbXENFT", {
            libraries: {
                MintInfo: mintinfo.address
            }
        });

        DBXENFTLocal = await dbXENFTLocal.deploy(xenft.address, XENContract.address, ethers.constants.AddressZero, ethers.constants.AddressZero);
        await DBXENFTLocal.deployed();
        expect(await DBXENFTLocal.alreadyUpdatePower(0)).to.equal(false);
        expect(Number(await DBXENFTLocal.totalPower())).to.equal(0);
        await xenft.approve(DBXENFTLocal.address, 10001);
        await DBXENFTLocal.burnNFT(deployer.address, 10001);
        expect(await DBXENFTLocal.alreadyUpdatePower(0)).to.equal(true);
        let actualTokensId = await xenft.ownedTokens();
        let lengthArray = Number(actualTokensId.length);
        expect(lengthArray).to.equal(0);
        expect(Number(await DBXENFTLocal.getCurrentCycle())).to.equal(0);
        expect(Number(await DBXENFTLocal.totalPower())).to.be.greaterThan(0);
        expect(Number(await DBXENFTLocal.lastActiveCycle(deployer.address))).to.equal(0);
    });

    it("Simple burn after claimable period", async() => {
        await XENContract.approve(xenft.address, ethers.utils.parseEther("100000000000000000"))
        await xenft.bulkClaimRank(128, 1);

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        const MintInfo = await ethers.getContractFactory("MintInfo", deployer)
        const mintinfo = await MintInfo.deploy()
        await mintinfo.deployed()

        const dbXENFTLocal = await ethers.getContractFactory("dbXENFT", {
            libraries: {
                MintInfo: mintinfo.address
            }
        });

        DBXENFTLocal = await dbXENFTLocal.deploy(xenft.address, XENContract.address, ethers.constants.AddressZero, ethers.constants.AddressZero);
        await DBXENFTLocal.deployed();
        expect(await DBXENFTLocal.alreadyUpdatePower(0)).to.equal(false);
        expect(Number(await DBXENFTLocal.userTotalPower(deployer.address))).to.equal(0);
        expect(Number(await DBXENFTLocal.totalPower())).to.equal(0);
        await xenft.approve(DBXENFTLocal.address, 10001);
        await DBXENFTLocal.burnNFT(deployer.address, 10001);
        expect(await DBXENFTLocal.alreadyUpdatePower(0)).to.equal(true);
        let actualTokensId = await xenft.ownedTokens();
        let lengthArray = Number(actualTokensId.length);
        let userPower = Number(await DBXENFTLocal.userTotalPower(deployer.address));
        let totalPower = Number(await DBXENFTLocal.totalPower());
        expect(lengthArray).to.equal(0);
        expect(Number(await DBXENFTLocal.getCurrentCycle())).to.equal(0);
        expect(userPower).to.be.greaterThan(0);
        expect(totalPower).to.be.greaterThan(0);
        expect(totalPower).to.equal(userPower);
        expect(Number(await DBXENFTLocal.lastActiveCycle(deployer.address))).to.equal(0);

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await XENContract.approve(xenft.address, ethers.utils.parseEther("100000000000000000"))
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(DBXENFTLocal.address, 10002);
        await DBXENFTLocal.burnNFT(deployer.address, 10002);
    });
});