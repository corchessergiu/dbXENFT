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

    it("Test DBX contract balance", async function() {
        let contractBalanceBeforeBurn = await ethers.provider.getBalance(dbXeNFTFactory.address);
        expect(contractBalanceBeforeBurn).to.equal("0");
        await xenft.bulkClaimRank(128, 71)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })
        let contractBalanceAfterBurn = await ethers.provider.getBalance(dbXeNFTFactory.address);
        expect(contractBalanceAfterBurn).to.be.greaterThan("0");
        let cycle0Reward = await dbXeNFTFactory.rewardPerCycle(0);
        expect(cycle0Reward).to.equal(ethers.utils.parseEther("10000"));

        let contractBalanceBeforeDeployerStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceBeforeDeployerStake).to.equal("0");
        await dbXeNFTFactory.stake(ethers.utils.parseEther("1000"), 0, { value: ethers.utils.parseEther("1") });
        let contractBalanceAfterDeployerStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceAfterDeployerStake).to.equal(ethers.utils.parseEther("1000"));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenftAlice.bulkClaimRank(64, 7)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })

        let contractBalanceBeforeAliceStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceBeforeAliceStake).to.equal(ethers.utils.parseEther("1000"));
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("100"), 1, { value: ethers.utils.parseEther("0.1") });
        let contractBalanceAfterAliceStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceAfterAliceStake).to.equal(ethers.utils.parseEther("1100"));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenftBob.bulkClaimRank(100, 100)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        let contractBalanceBeforeBobStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceBeforeBobStake).to.equal(ethers.utils.parseEther("1100"));
        let stakFeeBob = 0.001 * 2040;
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("2040"), 2, { value: ethers.utils.parseEther(stakFeeBob.toString()) });
        let contractBalanceAfterBobStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceAfterBobStake).to.equal(ethers.utils.parseEther("3140"));

        await xenftCarol.bulkClaimRank(32, 100)
        await xenftCarol.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryCarol.mintDBXENFT(10004, { value: ethers.utils.parseEther("1") })

        let contractBalanceBeforeCarolStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceBeforeCarolStake).to.equal(ethers.utils.parseEther("3140"));
        let stakFeeCarol = 0.001 * 1931;
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther("1931"), 3, { value: ethers.utils.parseEther(stakFeeCarol.toString()) });
        let contractBalanceAfterCarolStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceAfterCarolStake).to.equal(ethers.utils.parseEther("5071"));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenftDean.bulkClaimRank(77, 100)
        await xenftDean.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactoryDean.mintDBXENFT(10005, { value: ethers.utils.parseEther("1") })

        let contractBalanceBeforeDeanStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceBeforeDeanStake).to.equal(ethers.utils.parseEther("5071"));
        let stakFeeDean = 0.001 * 9671;
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther("9671"), 4, { value: ethers.utils.parseEther(stakFeeDean.toString()) });
        let contractBalanceAfterDeanStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceAfterDeanStake).to.equal(ethers.utils.parseEther("14742"));
    })

    it("Test the amount of eth sent as a fee", async function() {
        let contractBalanceBeforeBurn = await ethers.provider.getBalance(dbXeNFTFactory.address);
        expect(contractBalanceBeforeBurn).to.equal("0");
        await xenft.bulkClaimRank(128, 71)
        await xenft.approve(dbXeNFTFactory.address, 10001)
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") })
        let contractBalanceAfterBurn = await ethers.provider.getBalance(dbXeNFTFactory.address);
        expect(contractBalanceAfterBurn).to.be.greaterThan("0");

        let contractBalanceBeforeDeployerStake = await DBX.balanceOf(dbXeNFTFactory.address);
        expect(contractBalanceBeforeDeployerStake).to.equal("0");
        await dbXeNFTFactory.stake(ethers.utils.parseEther("1000"), 0, { value: ethers.utils.parseEther("1") });
        let contractBalanceAfterDeployerStake = await ethers.provider.getBalance(dbXeNFTFactory.address);
        expect(contractBalanceAfterDeployerStake).to.equal(contractBalanceAfterBurn.add(ethers.utils.parseEther("1")));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenftAlice.bulkClaimRank(64, 7)
        await xenftAlice.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryAlice.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })

        let contractBalanceBeforeAliceStake = await ethers.provider.getBalance(dbXeNFTFactory.address);
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("100"), 1, { value: ethers.utils.parseEther("0.1") });
        let contractBalanceAfterAliceStake = await ethers.provider.getBalance(dbXeNFTFactory.address);
        expect(contractBalanceAfterAliceStake).to.equal(contractBalanceBeforeAliceStake.add(ethers.utils.parseEther("0.1")));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenftBob.bulkClaimRank(100, 100)
        await xenftBob.approve(dbXeNFTFactory.address, 10003)
        await dbXeNFTFactoryBob.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        let contractBalanceBeforeBobStake = await ethers.provider.getBalance(dbXeNFTFactory.address);
        let stakFeeBob = 0.001 * 2040;
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("2040"), 2, { value: ethers.utils.parseEther(stakFeeBob.toString()) });
        let contractBalanceAfterBobStake = await ethers.provider.getBalance(dbXeNFTFactory.address);
        expect(contractBalanceAfterBobStake).to.equal(contractBalanceBeforeBobStake.add(ethers.utils.parseEther(stakFeeBob.toString())));

        await xenftCarol.bulkClaimRank(32, 100)
        await xenftCarol.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryCarol.mintDBXENFT(10004, { value: ethers.utils.parseEther("1") })

        let contractBalanceBeforeCarolStake = await ethers.provider.getBalance(dbXeNFTFactory.address);
        let stakFeeCarol = 0.001 * 1931;
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther("1931"), 3, { value: ethers.utils.parseEther(stakFeeCarol.toString()) });
        let contractBalanceAfterCarolStake = await ethers.provider.getBalance(dbXeNFTFactory.address);
        expect(contractBalanceAfterCarolStake).to.equal(contractBalanceBeforeCarolStake.add(ethers.utils.parseEther(stakFeeCarol.toString())));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        await xenftDean.bulkClaimRank(77, 100)
        await xenftDean.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactoryDean.mintDBXENFT(10005, { value: ethers.utils.parseEther("1") })

        let contractBalanceBeforeDeanStake = await ethers.provider.getBalance(dbXeNFTFactory.address);
        let stakFeeDean = 0.001 * 9671;
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther("9671"), 4, { value: ethers.utils.parseEther(stakFeeDean.toString()) });
        let contractBalanceAfterDeanStake = await ethers.provider.getBalance(dbXeNFTFactory.address);
        expect(contractBalanceAfterDeanStake).to.equal(contractBalanceBeforeDeanStake.add(ethers.utils.parseEther(stakFeeDean.toString())));
    })

    it("Test extra power for stake", async function() {
        //*** Cycle 0 ***
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(dbXeNFTFactory.address, 10001);

        const tx = await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") });

        let firstStakeAmount = 10;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactory.stake(ethers.utils.parseEther(firstStakeAmount.toString()), 0, { value: ethers.utils.parseEther("1") });

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24]);
        await hre.ethers.provider.send("evm_mine");

        //*** Cycle 1 ***
        await dbXeNFTFactory.stake(ethers.utils.parseEther("1"), 0, { value: ethers.utils.parseEther("0.001") });

        const basePow = await dbXeNFTFactory.baseDBXeNFTPower(0)
        let percentageValue = basePow.div(BigNumber.from(firstStakeAmount));
        let rewardCycle0 = await dbXeNFTFactory.rewardPerCycle(0);
        //Cycle 0, only one burn => total reward for deployer address = 10.000 power + extra power for 10 dnx stake => 11.000 power for deployer
        expect(await dbXeNFTFactory.dbxenftPower(0)).to.equal(percentageValue.add(rewardCycle0));

        await xenftAlice.bulkClaimRank(64, 7);
        await xenftAlice.approve(dbXeNFTFactory.address, 10002);
        await dbXeNFTFactoryAlice.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") });

        await xenftBob.bulkClaimRank(64, 7);
        await xenftBob.approve(dbXeNFTFactory.address, 10003);
        await dbXeNFTFactoryBob.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") });

        let firstStakeAmountAlice = "100";
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther(firstStakeAmountAlice), 1, { value: ethers.utils.parseEther("1") });

        let firstStakeAmountBob = "200";
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther(firstStakeAmountBob), 2, { value: ethers.utils.parseEther("1") });

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        //*** Cycle 2 -> without update reward because users does not burn anything*/
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("1"), 1, { value: ethers.utils.parseEther("0.001") })
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("1"), 2, { value: ethers.utils.parseEther("0.001") })

        const basePowNFT1 = await dbXeNFTFactory.baseDBXeNFTPower(1);
        const basePowNFT2 = await dbXeNFTFactory.baseDBXeNFTPower(2);
        let percentageValueAlice = basePowNFT1.mul(firstStakeAmountAlice).div(100)
        let percentageValueBob = basePowNFT2.mul(firstStakeAmountBob).div(100)

        let rewardCycle1 = await dbXeNFTFactory.rewardPerCycle(1);
        //Cycle 1, Alice burn one nft => get dbxennft with token id 1
        //Cycle 1, Bob burn one nft => get dbxennft with token id 2
        //They have same amount of reward for their nfts => from 10100 reward for cycle 1 both recieve 5.050
        //Alice stake 100 dbxen tokens => extrapower = 5.050   => total power now 10100
        //Bob stake 200 dbxen tokens => extrapower = 10.100 => total power now 15150
        expect(await dbXeNFTFactory.dbxenftPower(1)).to.equal(rewardCycle1.div(2).add(percentageValueAlice));
        expect(await dbXeNFTFactory.dbxenftPower(2)).to.equal(rewardCycle1.div(2).add(percentageValueBob));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        //*** Cycle 3 ***
        await xenftCarol.bulkClaimRank(32, 100)
        await xenftCarol.approve(dbXeNFTFactory.address, 10004)
        await dbXeNFTFactoryCarol.mintDBXENFT(10004, { value: ethers.utils.parseEther("1") })

        await xenftDean.bulkClaimRank(64, 100)
        await xenftDean.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactoryDean.mintDBXENFT(10005, { value: ethers.utils.parseEther("1") })

        let firstStakeAmountCarol = "150";
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther(firstStakeAmountCarol), 3, { value: ethers.utils.parseEther("1") });

        let firstStakeAmountDean = "300";
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther(firstStakeAmountDean), 4, { value: ethers.utils.parseEther("1") });

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24])
        await hre.ethers.provider.send("evm_mine")

        //*** Cycle 4 ***
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther("1"), 3, { value: ethers.utils.parseEther("0.001") })
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther("1"), 4, { value: ethers.utils.parseEther("0.001") })

        const basePowNFT3 = await dbXeNFTFactory.baseDBXeNFTPower(3);
        const basePowNFT4 = await dbXeNFTFactory.baseDBXeNFTPower(4);
        let percentageValueCarol = basePowNFT3.mul(firstStakeAmountCarol).div(100)
        let percentageValueDean = basePowNFT4.mul(firstStakeAmountDean).div(100)

        let rewardCycle2 = await dbXeNFTFactory.rewardPerCycle(3);
        let percentageValueFromCycle = rewardCycle2.div(3);
        expect(await dbXeNFTFactory.dbxenftPower(3)).to.equal(basePowNFT3.add(percentageValueCarol));
        expect(await dbXeNFTFactory.dbxenftPower(4)).to.equal(basePowNFT4.add(percentageValueDean));
    })

    it("Test extra power for stake whth gap cycles", async function() {
        //*** Cycle 0 ***
        await xenft.bulkClaimRank(128, 1);
        await xenft.approve(dbXeNFTFactory.address, 10001);
        await dbXeNFTFactory.mintDBXENFT(10001, { value: ethers.utils.parseEther("1") });

        await xenftCarol.bulkClaimRank(32, 100)
        await xenftCarol.approve(dbXeNFTFactory.address, 10002)
        await dbXeNFTFactoryCarol.mintDBXENFT(10002, { value: ethers.utils.parseEther("1") })

        await xenftDean.bulkClaimRank(64, 100)
        await xenftDean.approve(dbXeNFTFactory.address, 10003);
        await dbXeNFTFactoryDean.mintDBXENFT(10003, { value: ethers.utils.parseEther("1") })

        let deployerFirstStakeAmount = 10;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactory.stake(ethers.utils.parseEther(deployerFirstStakeAmount.toString()), 0, { value: ethers.utils.parseEther("1") });

        let carolFirstStakeAmount = 100;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther(carolFirstStakeAmount.toString()), 1, { value: ethers.utils.parseEther("1") });

        let deanFirstStakeAmount = 1000;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther(deanFirstStakeAmount.toString()), 2, { value: ethers.utils.parseEther("1") });

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24]);
        await hre.ethers.provider.send("evm_mine");

        //*** Cycle 1 ***
        await dbXeNFTFactory.stake(ethers.utils.parseEther("1"), 0, { value: ethers.utils.parseEther("0.001") });
        await dbXeNFTFactoryCarol.stake(ethers.utils.parseEther("1"), 1, { value: ethers.utils.parseEther("0.001") });
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther("1"), 2, { value: ethers.utils.parseEther("0.001") });

        const basePowDeployer = await dbXeNFTFactory.baseDBXeNFTPower(0)
        let percentageValue = basePowDeployer.mul(deployerFirstStakeAmount).div(100);
        expect(await dbXeNFTFactory.dbxenftPower(0)).to.equal(percentageValue.add(basePowDeployer));

        const basePowCarol = await dbXeNFTFactory.baseDBXeNFTPower(1)
        let percentageValueCarol = basePowCarol.mul(carolFirstStakeAmount).div(100);
        expect(await dbXeNFTFactory.dbxenftPower(1)).to.equal(percentageValueCarol.add(basePowCarol));

        const basePowDean = await dbXeNFTFactory.baseDBXeNFTPower(2)
        let percentageValueDean = basePowDean.mul(deanFirstStakeAmount).div(100);
        expect(await dbXeNFTFactory.dbxenftPower(2)).to.equal(percentageValueDean.add(basePowDean));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 3 * 24]);
        await hre.ethers.provider.send("evm_mine");

        await xenftAlice.bulkClaimRank(128, 12);
        await xenftAlice.approve(dbXeNFTFactory.address, 10004);
        await dbXeNFTFactoryAlice.mintDBXENFT(10004, { value: ethers.utils.parseEther("1") });

        await xenftBob.bulkClaimRank(32, 100)
        await xenftBob.approve(dbXeNFTFactory.address, 10005)
        await dbXeNFTFactoryBob.mintDBXENFT(10005, { value: ethers.utils.parseEther("1") })

        await xenftDean.bulkClaimRank(64, 100)
        await xenftDean.approve(dbXeNFTFactory.address, 10006);
        await dbXeNFTFactoryDean.mintDBXENFT(10006, { value: ethers.utils.parseEther("1") })

        let deployerSecondStakeAmount = 210;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther(deployerSecondStakeAmount.toString()), 3, { value: ethers.utils.parseEther("1") });

        let bobSecondStakeAmount = 132;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther(bobSecondStakeAmount.toString()), 4, { value: ethers.utils.parseEther("1") });

        let deanSecondStakeAmount = 192;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther(deanSecondStakeAmount.toString()), 5, { value: ethers.utils.parseEther("1") });

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24]);
        await hre.ethers.provider.send("evm_mine");

        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("1"), 3, { value: ethers.utils.parseEther("0.001") });
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("1"), 4, { value: ethers.utils.parseEther("0.001") });
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther("1"), 5, { value: ethers.utils.parseEther("0.001") });

        const basePowDeployerNFT3 = await dbXeNFTFactory.baseDBXeNFTPower(3)
        let percentageValueNFT3 = basePowDeployerNFT3.mul(deployerSecondStakeAmount).div(100);
        expect(await dbXeNFTFactoryAlice.dbxenftPower(3)).to.equal(percentageValueNFT3.add(basePowDeployerNFT3));

        const basePowBobNFT4 = await dbXeNFTFactory.baseDBXeNFTPower(4)
        let percentageValueBobNFT4 = basePowBobNFT4.mul(bobSecondStakeAmount).div(100);
        expect(await dbXeNFTFactoryBob.dbxenftPower(4)).to.equal(percentageValueBobNFT4.add(basePowBobNFT4));

        const basePowDeanNFT5 = await dbXeNFTFactory.baseDBXeNFTPower(5)
        let percentageValueDeanNFT5 = basePowDeanNFT5.mul(deanSecondStakeAmount).div(100);
        expect(await dbXeNFTFactoryDean.dbxenftPower(5)).to.equal(percentageValueDeanNFT5.add(basePowDeanNFT5));

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 13 * 24]);
        await hre.ethers.provider.send("evm_mine");

        await xenft.bulkClaimRank(128, 33);
        await xenft.approve(dbXeNFTFactory.address, 10007);
        await dbXeNFTFactory.mintDBXENFT(10007, { value: ethers.utils.parseEther("1") });

        await xenftAlice.bulkClaimRank(128, 25);
        await xenftAlice.approve(dbXeNFTFactory.address, 10008);
        await dbXeNFTFactoryAlice.mintDBXENFT(10008, { value: ethers.utils.parseEther("1") });

        await xenftBob.bulkClaimRank(32, 89)
        await xenftBob.approve(dbXeNFTFactory.address, 10009)
        await dbXeNFTFactoryBob.mintDBXENFT(10009, { value: ethers.utils.parseEther("1") })

        await xenftDean.bulkClaimRank(64, 61)
        await xenftDean.approve(dbXeNFTFactory.address, 10010);
        await dbXeNFTFactoryDean.mintDBXENFT(10010, { value: ethers.utils.parseEther("1") })

        let deployerThirdStakeAmount = 241;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactory.stake(ethers.utils.parseEther(deployerThirdStakeAmount.toString()), 6, { value: ethers.utils.parseEther("1") });

        let aliceThirdStakeAmount = 128;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther(aliceThirdStakeAmount.toString()), 7, { value: ethers.utils.parseEther("1") });

        let bobThirdStakeAmount = 31;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther(bobThirdStakeAmount.toString()), 8, { value: ethers.utils.parseEther("1") });

        let deanThirdStakeAmount = 812;
        await DBX.approve(dbXeNFTFactory.address, ethers.utils.parseEther("1001"));
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther(deanThirdStakeAmount.toString()), 9, { value: ethers.utils.parseEther("1") });

        await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24]);
        await hre.ethers.provider.send("evm_mine");

        await dbXeNFTFactory.stake(ethers.utils.parseEther("1"), 6, { value: ethers.utils.parseEther("0.001") });
        await dbXeNFTFactoryAlice.stake(ethers.utils.parseEther("1"), 7, { value: ethers.utils.parseEther("0.001") });
        await dbXeNFTFactoryBob.stake(ethers.utils.parseEther("1"), 8, { value: ethers.utils.parseEther("0.001") });
        await dbXeNFTFactoryDean.stake(ethers.utils.parseEther("1"), 9, { value: ethers.utils.parseEther("0.001") });

        const basePowDeployerNFT6 = await dbXeNFTFactory.baseDBXeNFTPower(6)
        let percentageValueNFT6 = basePowDeployerNFT6.mul(deployerThirdStakeAmount).div(100);
        expect(await dbXeNFTFactoryAlice.dbxenftPower(6)).to.equal(percentageValueNFT6.add(basePowDeployerNFT6));

        const basePowAliceNFT7 = await dbXeNFTFactory.baseDBXeNFTPower(7)
        let percentageValueAliceNFT7 = basePowAliceNFT7.mul(aliceThirdStakeAmount).div(100);
        expect(await dbXeNFTFactoryAlice.dbxenftPower(7)).to.equal(percentageValueAliceNFT7.add(basePowAliceNFT7));

        const basePowBobNFT8 = await dbXeNFTFactory.baseDBXeNFTPower(8)
        let percentageValueBobNFT8 = basePowBobNFT8.mul(bobThirdStakeAmount).div(100);
        expect(await dbXeNFTFactoryBob.dbxenftPower(8)).to.equal(percentageValueBobNFT8.add(basePowBobNFT8));

        const basePowDeanNFT9 = await dbXeNFTFactory.baseDBXeNFTPower(9)
        let percentageValueDeanNFT9 = basePowDeanNFT9.mul(deanThirdStakeAmount).div(100);
        expect(await dbXeNFTFactoryDean.dbxenftPower(9)).to.equal(percentageValueDeanNFT9.add(basePowDeanNFT9));
    })

})