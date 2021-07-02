const { expect } = require("chai");
const { artifacts } = require("hardhat");
const { web3tx, toWad, toBN } = require("@decentral.ee/web3-helpers");

const Asset = artifacts.require("Asset");

const deployFramework = require("@superfluid-finance/ethereum-contracts/scripts/deploy-framework");
const deployTestToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-test-token");
const deploySuperToken = require("@superfluid-finance/ethereum-contracts/scripts/deploy-super-token");
const SuperfluidSDK = require("@superfluid-finance/js-sdk");

const getTransferData = (returnData) => {
  return returnData.logs.find((x) => x.event === "Transfer").args;
};

describe("Asset Contract", () => {
  const errorHandler = (err) => {
    if (err) throw err;
  };

  let sf;
  let dai;
  let daix;

  let NFTAsset;
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
    NFTAsset = await Asset.new(
      "Asset Token",
      "AST",
      sf.host.address,
      sf.agreements.cfa.address,
      daix.address
    );

    users.app = sf.user({ address: NFTAsset.address, token: daix.address });
    users.app.alias = "App";
    
    for (const [, user] of Object.entries(users)) {
      if (user.alias === "App") continue;
      await web3tx(dai.mint, `${user.alias} mints many dai`)(
        user.address,
        toWad(mintAmount),
        {
          from: user.address,
        }
      );
      await web3tx(dai.approve, `${user.alias} approves daix`)(
        daix.address,
        toWad(mintAmount),
        {
          from: user.address,
        }
      );
      await web3tx(daix.upgrade, `${user.alias} approves daix`)(
        toWad(mintAmount),
        {
          from: user.address,
        }
      );
    }
  });

  it("Rent and Return Single Asset", async () => {
    let newAssetId = getTransferData(
      await NFTAsset.createAsset("TestAsset")
    ).tokenId.toNumber();

    let tokenURI = await NFTAsset.tokenURI(newAssetId);
    expect(tokenURI).to.equal("TestAsset");

    let initialOwner = await NFTAsset.ownerOf(newAssetId);
    expect(initialOwner).to.equal(deployer);

    await sf.cfa.createFlow({
      flowRate: flowRate.toString(),
      receiver: users.app.address,
      sender: addr1,
      superToken: daix.address,
      userData: web3.eth.abi.encodeParameter("uint256", newAssetId),
    });

    let currentOwner = await NFTAsset.ownerOf(newAssetId);
    expect(currentOwner).to.equal(addr1);

    await sf.cfa.deleteFlow({
      by: addr1,
      receiver: users.app.address,
      sender: addr1,
      superToken: daix.address,
      userData: web3.eth.abi.encodeParameter("uint256", newAssetId),
    });

    currentOwner = await NFTAsset.ownerOf(newAssetId);
    expect(currentOwner).to.equal(deployer);
  });
});
