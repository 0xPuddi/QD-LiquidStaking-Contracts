// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibLiquidStakingStorage } from "../libraries/LibLiquidStakingStorage.sol";
import { LibqdAVAXFacet } from "../libraries/LibqdAVAXFacet.sol";
import { LibERC20 } from "../libraries/LibERC20.sol";
import { IqdAVAX } from "../interfaces/IqdAVAX.sol";

import {LibDiamond} from "../../shared/libraries/LibDiamond.sol";
import { LibContext } from "../../shared/libraries/LibContext.sol";
import { LibReentrancyGuard } from "../../shared/libraries/LibReentrancyGuard.sol";

/**
 * QuarryDraw Staked AVAX contract.
 * 
 * Actual shares AVAX price := ( AVAX deposited * qdAVAX minted ) / AVAX managed
 * 
 * Actual AVAX amount per shares := (qdAVAX amount * AVAX managed) * qdAVAX minted
 * 
 * There is a 14 days cooldown to unstake your qdAVAX and a 1 day period to collect your request
 * if it is managed by the protocol.
 * The request on cooldown can be immediately fulfilled by arbitragieurs, and they will collect
 * a fee for their service. To be an arbitragieur you will have to hold any validator level share.
 * 
 * Fees distributed to arbitrageurs will decrease linearly as soon as the redeem request has been emitted.
 * We hope that this mechanism will both incentivize arbitrageurs to provide liquidity as soon as possible and
 * rewards redeemers that have not been satisfied by unwilling arbitrageurs with a full token backing of the request.
 * Fees will sclaed based on arbitrageur max level shares starting from 5%, to 4%, to 3%, to 2% and to 1% rate,
 * and it will be linearly decreased to 0% as the cooldown period comes to an end.
 * Price will be provided by the cost of shares in the exact moment an arbitrageurs fulfill a request and not
 * with the exchange rate on the time of the request, as this will help redeemers alleviate the fulfill request
 * time premium.
 * 
 */
contract qdAVAXFacet is IqdAVAX, LibReentrancyGuard {
    /**
     * @return The amount of shares that represents the value of deposit
     * according to AVAX controlled by the protocol.
     */
    function getSharesByStakedAvax(uint256 _valueDeposit) public view returns(uint256) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        if (lss.totalStakedAvax == 0) {
            return 0;
        }

        uint256 shares = ((_valueDeposit * lss.ERC20.totalSupply) / lss.totalStakedAvax);

        require(shares > 0, "Invalid share count");

        return shares;
    }

    /**
     * @notice Mint new liquid shares based on users deposited value
     */
    function mintNewShares() public payable nonReentrant() returns(uint256) {
        LibLiquidStakingStorage.mintPaused();
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        address sender = LibContext._msgSender();
        uint256 valueDeposit = msg.value;
        uint256 shareAmount;

        require(valueDeposit > 0, "ZERO_DEPOSIT_VALUE");
        
        shareAmount = getSharesByStakedAvax(valueDeposit);
        if (shareAmount == 0) {
            shareAmount = valueDeposit;
        }

        LibERC20._mint(sender, shareAmount);

        lss.totalStakedAvax += valueDeposit;

        emit newShares(sender, valueDeposit, shareAmount);

        return shareAmount;
    }

    /**
     * @notice Request a redeem. Multiple requests don't reset cooldown
     */
    function requestRedeem(uint256 _shares) external nonReentrant() returns(uint256) {
        LibLiquidStakingStorage.redeemPause();
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        address sender = LibContext._msgSender();
        uint256 _time = block.timestamp;

        require(_shares > 0, "INVALID_SHARES");
        require(_shares <= lss.ERC20.balances[sender], "NOT_ENOUGH_SHARES_OWNED");

        lss.sharesDeposited[sender] += _shares;
        LibERC20._transfer(sender, address(this), _shares);

        lss.redeemRequest[sender].push(LibLiquidStakingStorage.RedeemRequestStruct(
            _time,
            _shares
        ));

        if (!(lss.isRedeeming[sender])) {
           lss.redeemers.push(sender);
           lss.redeemersIndex[sender] = lss.redeemers.length - 1;
           lss.isRedeeming[sender] = true;
        }

        emit redeemRequest(sender, _shares, _time);

        return _time;
    }

    /**
     * @notice Cancel all pending redeem requests waiting the cooldown period to elapse.
     */
    function cancelPendingRedeemRequests() external nonReentrant() {
        LibLiquidStakingStorage.redeemPause();
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256 redeemIndex;
        address user = LibContext._msgSender();

        while (redeemIndex < lss.redeemRequest[user].length) {
            if (!LibqdAVAXFacet._isWithinCooldownPeriod(lss.redeemRequest[user][redeemIndex])) {
                redeemIndex += 1;
                continue;
            }

            LibqdAVAXFacet._cancelRedeemRequest(redeemIndex);
        }
    }

    /**
     * @notice Cancel all redeem requests that are redeemable.
     */
    function cancelRedeemableUnlockRequests() external nonReentrant() {
        LibLiquidStakingStorage.redeemPause();
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256 redeemIndex;
        address user = LibContext._msgSender();

        while (redeemIndex < lss.redeemRequest[user].length) {
            if (!LibqdAVAXFacet._isWithinRedeemPeriod(lss.redeemRequest[user][redeemIndex])) {
                redeemIndex += 1;
                continue;
            }

            LibqdAVAXFacet._cancelRedeemRequest(redeemIndex);
        }
    }

    /**
     * @notice Cancel an unexpired unlock request
     * @param redeemIndex Index number of the cancelled unlock
     */
    function cancelUnlockRequest(uint256 redeemIndex) external nonReentrant() {
        LibLiquidStakingStorage.redeemPause();
        LibqdAVAXFacet._cancelRedeemRequest(redeemIndex);
    }

    /**
     * @notice Redeem all redeemable AVAX from all redeem requests by owner
     */
    function redeemAllOwner() external nonReentrant() {
        LibLiquidStakingStorage.redeemPause();
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        address user = LibContext._msgSender();
        LibLiquidStakingStorage.RedeemRequestStruct[] memory _allUserRedeemRequest = lss.redeemRequest[user];
        uint256 lengthRequests = _allUserRedeemRequest.length;
        uint256 i = 0;

        while (i < lengthRequests) {
            if (!LibqdAVAXFacet._isWithinRedeemPeriod(_allUserRedeemRequest[i])) {
                unchecked {
                    ++i;
                }
                continue;
            }

            LibqdAVAXFacet._redeemAfterCooldown(i);

            lengthRequests -= 1;
        }
    }

    /**
     * @notice Redeem AVAX after cooldown has finished by owner
     * @param index Index number of the redeemed request
     */
    function redeemOwner(uint256 index) external nonReentrant() {
        LibLiquidStakingStorage.redeemPause();
        LibqdAVAXFacet._redeemAfterCooldown(index);
    }

    /**
     * @notice Redeem all sAVAX held in custody for overdue unlock requests
     */
    function redeemAllExpiredShares() external nonReentrant() {
        LibLiquidStakingStorage.redeemPause();
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256 totalExpiredShares = 0;
        address user = LibContext._msgSender();
        uint256 redeemCount = lss.redeemRequest[user].length;
        uint256 i = 0;

        while (i < redeemCount) {
            LibLiquidStakingStorage.RedeemRequestStruct memory redeemRequestUser = lss.redeemRequest[user][i];

            if (!LibqdAVAXFacet._isExpired(redeemRequestUser)) {
                i += 1;
                continue;
            }

            totalExpiredShares += redeemRequestUser.requestAmount;

            lss.redeemRequest[user][i] = lss.redeemRequest[user][lss.redeemRequest[user].length - 1];
            lss.redeemRequest[user].pop();

            redeemCount -= 1;
        }

        if (lss.redeemRequest[user].length == 0 && lss.isRedeeming[user]) {
            uint256 oldIndex = lss.redeemersIndex[user];
            address lastMember = lss.redeemers[lss.redeemers.length - 1];

            lss.redeemers[oldIndex] = lastMember;
            lss.redeemers.pop();

            lss.redeemersIndex[lastMember] = oldIndex;
            
            delete lss.redeemersIndex[user];
            
            delete lss.isRedeeming[user];
        }

        if (totalExpiredShares > 0) {
            lss.sharesDeposited[user] -= totalExpiredShares;
            LibERC20._transfer(address(this), msg.sender, totalExpiredShares);

            emit RedeemExpiredShares(user, totalExpiredShares);
        }
    }

    /**
     * @notice Redeem qdAVAX held in custody for the given redeem request after expiry
     * @param index Unlock request array index
     */
    function redeemExpiredShares(uint256 index) external nonReentrant() {
        LibLiquidStakingStorage.redeemPause();
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        address user = LibContext._msgSender();

        require(index < lss.redeemRequest[user].length, "INVALID_INDEX");

        LibLiquidStakingStorage.RedeemRequestStruct memory redeemRequestUser = lss.redeemRequest[user][index];

        require(LibqdAVAXFacet._isExpired(redeemRequestUser), "REQUEST_NOT_EXPIRED");

        uint256 shareAmount = redeemRequestUser.requestAmount;
        lss.sharesDeposited[user] -= shareAmount;

        lss.redeemRequest[user][index] = lss.redeemRequest[user][lss.redeemRequest[user].length - 1];
        lss.redeemRequest[user].pop();

        if (lss.redeemRequest[user].length == 0 && lss.isRedeeming[user]) {
            uint256 oldIndex = lss.redeemersIndex[user];
            address lastMember = lss.redeemers[lss.redeemers.length - 1];

            lss.redeemers[oldIndex] = lastMember;
            lss.redeemers.pop();

            lss.redeemersIndex[lastMember] = oldIndex;
            
            delete lss.redeemersIndex[user];
            
            delete lss.isRedeeming[user];
        }

        LibERC20._transfer(address(this), user, shareAmount);

        emit RedeemExpiredShares(user, shareAmount);
    }

    /**
     * @notice Fulfill a redeem request by arbitrageur
     * @param redeemer User to be redeemed by arbitrageurs
     * @param index Index of the redeem request by user
     */
    function fulfillRedeemingRequestArbitrageur(address redeemer, uint256 index) external payable nonReentrant() returns(bool) {
        LibLiquidStakingStorage.redeemPause();
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256[] memory validatorBalanceOfArbitrageur = new uint256[](5);
        uint256 lastIndex = 5;
        address arbitrageur = LibContext._msgSender();
        LibLiquidStakingStorage.RedeemRequestStruct memory redeemRequestUser = lss.redeemRequest[redeemer][index];

        for (uint256 i = 0; i < 5; ) {
            validatorBalanceOfArbitrageur[i] = lss.IAvalancheValidators[0].balanceOf(arbitrageur, i);
            if (validatorBalanceOfArbitrageur[i] > 0) {
                lastIndex = i;
            }
            unchecked {
                ++i;
            }
        }

        require(lastIndex < 5, "NOT_VALIDATOR_HOLDER");
        require(LibqdAVAXFacet._isWithinCooldownPeriod(redeemRequestUser), "NOT_WITHIN_COOLDOWN_PERIOD");

        uint256 arbitrageurCost = LibqdAVAXFacet._calculateArbitrageursPrice(lastIndex, redeemRequestUser);

        require(arbitrageurCost > 0 && arbitrageurCost <= msg.value, "INCORRECT_VALUE_DEPOSITED");
        require(LibqdAVAXFacet._manageArbitrageursRequest(arbitrageur, redeemer, redeemRequestUser, msg.value, block.timestamp), "REQUEST_FAILED");

        lss.redeemRequest[redeemer][index] = lss.redeemRequest[redeemer][lss.redeemRequest[redeemer].length - 1];
        lss.redeemRequest[redeemer].pop();

        if (lss.redeemRequest[redeemer].length == 0 && lss.isRedeeming[redeemer]) {
            uint256 oldIndex = lss.redeemersIndex[redeemer];
            address lastMember = lss.redeemers[lss.redeemers.length - 1];

            lss.redeemers[oldIndex] = lastMember;
            lss.redeemers.pop();

            lss.redeemersIndex[lastMember] = oldIndex;
            
            delete lss.redeemersIndex[redeemer];
            
            delete lss.isRedeeming[redeemer];
        }

        emit ArbitrageurFulfilledRequest(arbitrageur, redeemer, redeemRequestUser.requestAmount, msg.value, block.timestamp);

        return true;
    }

    /**
     * @notice Withdraw qdAVAX bought by arbitrageurs after vesting period
     */
    function withdrawSharesArbitraged(uint256 index) external nonReentrant() returns(bool) {
        LibLiquidStakingStorage.redeemPause();
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256[] memory validatorBalanceOfArbitrageur = new uint256[](5);
        uint256 lastIndex = 5;
        address arbitrageur = LibContext._msgSender();

        for (uint256 i = 0; i < 5; ) {
            validatorBalanceOfArbitrageur[i] = lss.IAvalancheValidators[0].balanceOf(arbitrageur, i);
            if (validatorBalanceOfArbitrageur[i] > 0) {
                lastIndex = i;
            }
            unchecked {
                ++i;
            }
        }

        require(lastIndex < 5, "NOT_VALIDATOR_HOLDER");

        (uint256 availableRewards, uint256 linearRewards, uint256 arbitrageAmount) = LibqdAVAXFacet._linearVestingArbitrageurs(arbitrageur, lastIndex, index);

        require(arbitrageAmount > 0, "INVALID_INDEX");

        if (availableRewards > 0) {
            lss.sharesDeposited[arbitrageur] -= availableRewards;
            lss.arbitrageursRedeem[arbitrageur][index].arbitrageAmountCollected += availableRewards;

            if (linearRewards == arbitrageAmount) {
                lss.arbitrageursRedeem[arbitrageur][index] = lss.arbitrageursRedeem[arbitrageur][lss.arbitrageursRedeem[arbitrageur].length - 1];
                lss.arbitrageursRedeem[arbitrageur].pop();
            }

            LibERC20._transfer(address(this), arbitrageur, availableRewards);
        }
        
        emit ArbitrageurWithdrawRequest(arbitrageur, index, availableRewards, arbitrageAmount - linearRewards, block.timestamp);

        return true;
    }
}