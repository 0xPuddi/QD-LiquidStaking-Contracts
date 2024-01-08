/* global describe it before ethers */
const { ethers, network, provider, hre } = require("hardhat");

const {
    getSelectors,
    FacetCutAction,
    removeSelectors,
    findAddressPositionInFacets
} = require('../scripts/libraries/diamond.js');

const { deployDiamond } = require('../scripts/deploy.js');

const { assert, expect } = require('chai');

describe('DiamondTest', async function () {
    let diamondAddress;
    let diamondCutFacet;
    let diamondLoupeFacet;
    let ownershipFacet;
    let ERC20Facet;
    let qdAVAXSettingsFacet;
    let qdAVAXSettingsFacet_address0;
    let qdAVAXFacet;
    let qdAVAXFacet_address0;
    let qdAVAXFacet_address1;
    let qdAVAXFacet_address2;
    let qdAVAXViewFacet;
    let testERC1155;
    let tx;
    let receipt;
    let result;
    const addresses = [];
    let users = [];

    before(async function () {
        // get contracts ABIs
        diamondAddress = await deployDiamond();
        diamondCutFacet = await ethers.getContractAt('DiamondCutFacet', diamondAddress.diamond);
        diamondLoupeFacet = await ethers.getContractAt('DiamondLoupeFacet', diamondAddress.diamond);
        ownershipFacet = await ethers.getContractAt('OwnershipFacet', diamondAddress.diamond);
        ERC20Facet = await ethers.getContractAt('ERC20Facet', diamondAddress.diamond);
        qdAVAXSettingsFacet = await ethers.getContractAt('qdAVAXSettingsFacet', diamondAddress.diamond);
        qdAVAXFacet = await ethers.getContractAt('qdAVAXFacet', diamondAddress.diamond);
        qdAVAXViewFacet = await ethers.getContractAt('qdAVAXViewFacet', diamondAddress.diamond);

        // testERC1155
        testERC1155 = await ethers.getContractAt('testERC1155', diamondAddress.ERC1155);

        // get addresse
        for (const address of await diamondLoupeFacet.facetAddresses()) {
            addresses.push(address);
        };

        // get signers
        users = await ethers.getSigners();

        // contracts instances
        qdAVAXSettingsFacet_address0 = qdAVAXSettingsFacet.connect(users[0]);

        qdAVAXFacet_address0 = qdAVAXFacet.connect(users[0]);
        qdAVAXFacet_address1 = qdAVAXFacet.connect(users[1]);
        qdAVAXFacet_address2 = qdAVAXFacet.connect(users[2]);
    });

    it("mint new shares", async () => {
        tx = await testERC1155._mintBatch(users[0].address, [0, 1, 2, 3, 4], [1, 1, 1, 1, 1], "0x");
        await tx.wait(1);

        tx = await testERC1155._mintBatch(users[1].address, [0, 1, 2, 3, 4], [0, 0, 0, 0, 4], "0x");
        await tx.wait(1);

        tx = await testERC1155._mintBatch(users[2].address, [0, 1, 2, 3, 4], [0, 3, 0, 0, 0], "0x");
        await tx.wait(1);

        assert.equal((await testERC1155.balanceOfBatch([users[0].address, users[0].address, users[0].address, users[0].address, users[0].address], [0, 1, 2, 3, 4])).toString(), '1,1,1,1,1', 'balance user 0');
        assert.equal((await testERC1155.balanceOfBatch([users[1].address, users[1].address, users[1].address, users[1].address, users[1].address], [0, 1, 2, 3, 4])).toString(), '0,0,0,0,4', 'balance user 1');
        assert.equal((await testERC1155.balanceOfBatch([users[2].address, users[2].address, users[2].address, users[2].address, users[2].address], [0, 1, 2, 3, 4])).toString(), '0,3,0,0,0', 'balance user 2');
    });

    it("mint shares", async () => {
        tx = await qdAVAXFacet_address0.mintNewShares({ value: ethers.utils.parseEther("0.1") });
        await tx.wait(1);

        tx = await qdAVAXFacet_address1.mintNewShares({ value: ethers.utils.parseEther("0.07") });
        await tx.wait(1);

        tx = await qdAVAXFacet_address2.mintNewShares({ value: ethers.utils.parseEther("0.5") });
        await tx.wait(1);

        assert.equal((await ERC20Facet.balanceOf(users[0].address)).toString(), "" + 1e17, "balance user 0");
        assert.equal((await ERC20Facet.balanceOf(users[1].address)).toString(), "" + 7e16, "balance user 1");
        assert.equal((await ERC20Facet.balanceOf(users[2].address)).toString(), "" + 5e17, "balance user 2");
    });

    it("test rewards", async () => {
        assert.equal((await qdAVAXFacet.getSharesByStakedAvax(ethers.utils.parseEther("1.0"))).toString(), "" + 1e18, "Same value as of no rewards");

        tx = await qdAVAXSettingsFacet_address0.depositRewards({ value: ethers.utils.parseEther("1.0") });
        await tx.wait(1);

        assert.isBelow(Number((await qdAVAXFacet.getSharesByStakedAvax(ethers.utils.parseEther("1.0"))).toString()), 1e18, "Shares cost more AVAX");
        assert.isAbove(Number((await qdAVAXViewFacet.getStakedAvaxByShares(ethers.utils.parseEther("1.0"))).toString()), 1e18, "Shares worth more AVAX");
    });

    it("test redeems asks", async () => {
        tx = await qdAVAXFacet_address1.requestRedeem(ethers.utils.parseEther("0.02"));
        receipt = await tx.wait(1);
        tx = await qdAVAXFacet_address2.requestRedeem(ethers.utils.parseEther("0.2"));
        await tx.wait(1);

        assert.equal((await ERC20Facet.balanceOf(users[1].address)).toString(), "" + 5e16, "balance user 1");
        assert.equal((await ERC20Facet.balanceOf(users[2].address)).toString(), "" + 3e17, "balance user 2");
        assert.equal((await qdAVAXViewFacet.getRedeemersArray()).toString(), '' + users[1].address + ',' + users[2].address, 'Invalid redeeemers array');
        assert.equal((await qdAVAXViewFacet.getRedeemerRedeemsNumber(users[1].address)).toString(), '1', 'Invalid redeeemers amount 1');
        assert.equal((await qdAVAXViewFacet.getRedeemerRedeemsNumber(users[2].address)).toString(), '1', 'Invalid redeeemers amount 2');

        tx = await qdAVAXFacet_address2.requestRedeem(ethers.utils.parseEther("0.04")); // 0.159402985074626865 - 0 late over periods
        await tx.wait(1);
        await network.provider.send("evm_increaseTime", [24 * 60 * 60]);
        await network.provider.send("evm_mine");
        tx = await qdAVAXFacet_address2.requestRedeem(ethers.utils.parseEther("0.02")); // 3.985074626865671641 - 1 redeem
        await tx.wait(1);
        await network.provider.send("evm_increaseTime", [60 * 60 * 24 * 7 + 60]);
        await network.provider.send("evm_mine");
        tx = await qdAVAXSettingsFacet_address0.depositRewards({ value: ethers.utils.parseEther("1.0") });
        await tx.wait(1);
        await network.provider.send("evm_increaseTime", [60 * 60 * 24 * 7 + 60]);
        await network.provider.send("evm_mine");
        tx = await qdAVAXFacet_address2.requestRedeem(ethers.utils.parseEther("0.01")); // 0.039850746268656716 - 0 early cooldown
        await tx.wait(1);

        tx = await qdAVAXFacet_address2.cancelRedeemableUnlockRequests();
        await tx.wait(1);
        await expect(qdAVAXFacet_address2.redeemExpiredShares(2)).to.be.revertedWith('REQUEST_NOT_EXPIRED');
        tx = await qdAVAXFacet_address2.cancelPendingRedeemRequests();
        await tx.wait(1);

        await network.provider.send("evm_increaseTime", [60 * 60 * 24 * 15 + 60]);
        await network.provider.send("evm_mine");
        tx = await qdAVAXFacet_address2.redeemExpiredShares(1);
        await tx.wait(1);

        tx = await qdAVAXFacet_address2.redeemAllExpiredShares();
        await tx.wait(1);
        await expect(qdAVAXViewFacet.getRedeemerInfoFromTo(users[2].address, 0, 6)).to.be.revertedWith('FROM_OUT_OF_BONDS');
        tx = await qdAVAXFacet_address0.redeemAllExpiredShares();
        await tx.wait(1);
        tx = await qdAVAXFacet_address1.redeemAllExpiredShares();
        await tx.wait(1);
    });

    it("test arbitrageurs role", async () => {
        tx = await qdAVAXFacet_address2.requestRedeem(ethers.utils.parseEther("0.04"));
        await tx.wait(1);
        tx = await qdAVAXFacet_address2.requestRedeem(ethers.utils.parseEther("0.02"));
        await tx.wait(1);
        tx = await qdAVAXFacet_address1.requestRedeem(ethers.utils.parseEther("0.01"));
        await tx.wait(1);

        tx = await qdAVAXFacet_address0.fulfillRedeemingRequestArbitrageur(users[2].address, 1, { value: ethers.utils.parseEther("0.1") });
        await tx.wait(1);

        tx = await qdAVAXFacet_address2.fulfillRedeemingRequestArbitrageur(users[1].address, 0, { value: ethers.utils.parseEther("0.1") });
        await tx.wait(1);

        await expect(qdAVAXViewFacet.getArbitrageurInfo(users[1].address, 0)).to.be.revertedWith('INDEX_OUT_OF_BONDS_OR_NULL');

        await network.provider.send("evm_increaseTime", [60 * 60 * 24 * 2 + 60]);
        await network.provider.send("evm_mine");

        tx = await qdAVAXFacet_address0.withdrawSharesArbitraged(0);
        await tx.wait(1);
        tx = await qdAVAXFacet_address2.withdrawSharesArbitraged(0);
        await tx.wait(1);
    });
});