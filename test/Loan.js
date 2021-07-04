const { expect } = require("chai");
const { artifacts } = require("hardhat");
const { web3tx, toWad, toBN } = require("@decentral.ee/web3-helpers");

const Loan = artifacts.require("Loan");

const deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework");
const deployTestToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-test-token");
const deploySuperToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-super-token");
const SuperfluidSDK = require("@superfluid-finance/js-sdk");

const getTransferData = returnData => {
  return returnData.logs.find(x => x.event === "Transfer").args;
};

describe("Loan", () => {
  const errorHandler = err => {
    if (err) throw err;
  };

  let sf;
  let dai;
  let daix;

  let loan; // contract Loan
  let accounts;
  let names;
  let users = {};

  let flowRate = toWad("1").div(toBN(3600));
  let mintAmount = 100;

  before(async () => {
    [deployer, addr1, addr2] = await web3.eth.getAccounts();
    accounts = [deployer, addr1, addr2];
    names = ["deployer", "addr1", "addr2"];

    await deployFramework(errorHandler, {
      web3,
      from: deployer,
    });

    await deployTestToken(errorHandler, [":", "fDAI"], {
      web3,
      from: deployer,
    });

    await deploySuperToken(errorHandler, [":", "fDAI"], {
      web3,
      from: deployer,
    });

    sf = new SuperfluidSDK.Framework({
      web3,
      version: "test",
      tokens: ["fDAI"],
    });

    await sf.initialize();
    daix = sf.tokens.fDAIx;
    dai = await sf.contracts.TestToken.at(await sf.tokens.fDAI.address);

    for (var i = 0; i < names.length; i++) {
      users[names[i].toLowerCase()] = sf.user({
        address: accounts[i],
        token: daix.address,
      });
      users[names[i].toLowerCase()].alias = names[i];
    }
  });

  beforeEach(async () => {
    // deploy contract Loan
    loan = await Loan.new("Loan Token", "DEBT", sf.host.address, sf.agreements.cfa.address, daix.address);

    users.app = sf.user({ address: loan.address, token: daix.address });
    users.app.alias = "App";

    for (const [, user] of Object.entries(users)) {
      if (user.alias === "App") continue;
      await web3tx(dai.mint, `${user.alias} mints many dai`)(user.address, toWad(mintAmount), {
        from: user.address,
      });
      await web3tx(dai.approve, `${user.alias} approves daix`)(daix.address, toWad(mintAmount), {
        from: user.address,
      });
      await web3tx(daix.upgrade, `${user.alias} approves daix`)(toWad(mintAmount), {
        from: user.address,
      });
    }
  });

  it("should create a loan and addr1 becomes the creditor of that loan", async () => {
    await loan.createLoan();
    await loan.lend(1, { from: addr1, value: web3.utils.toWei("1", "ether") });
    const { creditor } = await loan.loanCreditor(1);
    expect(creditor).to.equal(addr1);
  });

  it("get the flow", async () => {
    await loan.createLoan();
    await loan.lend(1, { from: addr1, value: web3.utils.toWei("1", "ether") });
    const creditorBefore = await loan.loanCreditor(1);
    console.log("before flowRate: ", creditorBefore.flowRate.toString());

    await sf.cfa.createFlow({
      flowRate: flowRate.toString(),
      receiver: users.app.address,
      sender: deployer,
      superToken: daix.address,
      userData: web3.eth.abi.encodeParameter("uint256", 1), // tokenId == 1
    });

    const creditorAfter = await loan.loanCreditor(1);
    console.log("after flowRate: ", creditorAfter.flowRate.toString());

    // let loanId = getTransferData(await loan.createLoan("TestLoan")).tokenId.toNumber();
    // expect(loanId).to.equal(1);
    // const resTokenReceiver = await loan.tokenReceiver(loanId);
    // expect(resTokenReceiver.receiver).to.equal(deployer);
    // let loanId2 = getTransferData(await loan.createLoan("TestLoan", { from: addr1 })).tokenId.toNumber();
    // expect(loanId2).to.equal(2);
    // const resTokenReceiver2 = await loan.tokenReceiver(loanId2, { from: addr1 });
    // expect(await loan.ownerOf(loanId2, { from: addr1 })).to.equal(addr1);
    // expect(resTokenReceiver2.receiver).to.equal(addr1);
  });
});
