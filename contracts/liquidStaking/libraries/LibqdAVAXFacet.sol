// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibLiquidStakingStorage } from "../libraries/LibLiquidStakingStorage.sol";
import { LibERC20 } from "../libraries/LibERC20.sol";

import {LibDiamond} from "../../shared/libraries/LibDiamond.sol";
import { LibContext } from "../../shared/libraries/LibContext.sol";

/**
 * QuarryDraw Staked AVAX internal fuctions library.
 */
library LibqdAVAXFacet {
    /// Emitted at owner redeeming after cooldown period
    event RedeemOwner(address indexed redeemer, uint256 requestTime, uint256 requestAmount, uint256 avaxAmount);
    /// Emitted at owner redeeming after cooldown period
    event RedeemArbitrageur(address indexed arbitrageur, address indexed owner, uint256 requestTime, uint256 requestAmount, uint256 feeAmount, uint256 avaxAmount);
    /// Emit at cancelled redeemer request
    event CancelRedeem(address indexed redeemer, uint256 requestTime, uint256 requestAmount);

    /**
     * @notice Internal {getStakedAvaxByShares}
     */
    function _getStakedAvaxByShares(uint256 _shareAmount) internal view returns(uint256) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        if (lss.ERC20.totalSupply == 0) {
            return 0;
        }

        return ((_shareAmount * lss.totalStakedAvax) / lss.ERC20.totalSupply);
    }

    /**
     * @notice Get the earliest exchange rate closest to the timestamp after cooldown period
     * @param _timestamp timestamp
     * @return (success, exchange rate)
     */
    function _getExchangeRateByUnlockTimestamp(uint256 _timestamp) internal view returns(bool, uint256) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        if (lss.timestampsExchangeRates.length == 0) {
            return (false, 0);
        }

        uint256 low = 0;
        uint256 mid;
        uint256 high = lss.timestampsExchangeRates.length - 1;

        uint256 unlockTimestamp = _timestamp + lss.cooldownPeriod;

        while (low <= high) {
            mid = (high + low) / 2;

            if (lss.timestampsExchangeRates[mid] <= unlockTimestamp) {
                if (mid + 1 == lss.timestampsExchangeRates.length ||
                    lss.timestampsExchangeRates[mid + 1] > unlockTimestamp) {
                    return (true, lss.exchangeRatesByTimestamp[lss.timestampsExchangeRates[mid]]);
                }

                low = mid + 1;
            } else if (mid == 0) {
                return (true, 1e18);
            } else {
                high = mid - 1;
            }
        }

        return (false, 0);
    }

    /**
     * @notice Checks if the redeem request is within its redeeming period
     * @param _redeemRequest Redeem request
     */
    function _isWithinRedeemPeriod(LibLiquidStakingStorage.RedeemRequestStruct memory _redeemRequest) internal view returns(bool) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();
        return !_isWithinCooldownPeriod(_redeemRequest)
            && _redeemRequest.requestTime + lss.cooldownPeriod + lss.redeemPeriod >= block.timestamp;
    }

    /**
     * @notice Checks if the redeem request is within its cooldown period
     * @param _redeemRequest Redeem request
     */
    function _isWithinCooldownPeriod(LibLiquidStakingStorage.RedeemRequestStruct memory _redeemRequest) internal view returns(bool) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();
        return _redeemRequest.requestTime + lss.cooldownPeriod >= block.timestamp;
    }

    /**
     * @notice Checks if the redeem request has expired
     * @param _redeemRequest Redeem request
     */
    function _isExpired(LibLiquidStakingStorage.RedeemRequestStruct memory _redeemRequest) internal view returns(bool) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();
        return _redeemRequest.requestTime + lss.cooldownPeriod + lss.redeemPeriod < block.timestamp;
    }

    /**
     * @notice Remove exchange rate entries older than `redeemPeriod`
     */
    function _dropExpiredExchangeRateEntries() internal {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        if (lss.timestampsExchangeRates.length == 0) {
            return;
        }

        uint256 timestampsIndex = 0;
        uint256 timestampsExpiration = block.timestamp - lss.redeemPeriod - 2 days;

        while (timestampsIndex < lss.timestampsExchangeRates.length &&
            lss.timestampsExchangeRates[timestampsIndex] < timestampsExpiration) {
            timestampsIndex += 1;
        }

        if (timestampsIndex == 0) {
            return;
        }

        for (uint256 i = 0; i < (lss.timestampsExchangeRates.length - timestampsIndex); ) {
            lss.timestampsExchangeRates[i] = lss.timestampsExchangeRates[i + timestampsIndex];
            unchecked {
                ++i;
            }
        }

        for (uint256 i = 1; i <= timestampsIndex; ) {
            lss.timestampsExchangeRates.pop();
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Calculate arbitrageurs shares price, based on level and time of the arbitrage
     * @param holderLevel Level of share that the arbitrageurs is holding
     * @param _redeemRequestUser User redeem request
     */
    function _calculateArbitrageursPrice(uint256 holderLevel, LibLiquidStakingStorage.RedeemRequestStruct memory _redeemRequestUser) internal view returns(uint256) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256 avaxCostOfShares = _getStakedAvaxByShares(_redeemRequestUser.requestAmount);
        uint256 _LPfee = lss.LPfees[holderLevel];
        uint256 _PERCENTAGE_PRECISION = lss.PERCENTAGE_PRECISION;
        uint256 _time = block.timestamp;

        uint256 linearLPFee = (_LPfee * _redeemRequestUser.requestTime) / _time;

        return (avaxCostOfShares - (avaxCostOfShares * linearLPFee) / _PERCENTAGE_PRECISION);
    }

    /**
     * @notice Calculate linear vesting for arbitrageurs
     */
    function _linearVestingArbitrageurs(address arbitrageurs, uint256 holderLevel, uint256 requestIndex) internal view returns(uint256, uint256, uint256) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256 vestingTime = lss.LPVestingPeriods[holderLevel];
        LibLiquidStakingStorage.ArbitrageursRedeemStruct memory requestArbitrageur = lss.arbitrageursRedeem[arbitrageurs][requestIndex];
        uint256 _time = block.timestamp;

        if (requestArbitrageur.arbitrageTime == 0 || requestArbitrageur.arbitrageAmount == 0) {
            return(0, 0, 0);
        }

        uint256 linearRewards = (requestArbitrageur.arbitrageAmount * (_time - requestArbitrageur.arbitrageTime)) / vestingTime;

        if (linearRewards > requestArbitrageur.arbitrageAmount) {
            linearRewards = requestArbitrageur.arbitrageAmount;
        }

        uint256 availableRewards = linearRewards - requestArbitrageur.arbitrageAmountCollected;

        return(availableRewards, linearRewards, requestArbitrageur.arbitrageAmount);
    }

    /**
     * @notice Redeem AVAX after cooldown has finished
     * @param redeemRequestIndex Index number of the redeemed unlock request
     */
    function _redeemAfterCooldown(uint256 redeemRequestIndex) internal {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        address user = LibContext._msgSender();

        require(redeemRequestIndex < lss.redeemRequest[user].length, "INVALID_REDEEM_INDEX");

        LibLiquidStakingStorage.RedeemRequestStruct memory _redeemRequest = lss.redeemRequest[user][redeemRequestIndex];

        require(_isWithinRedeemPeriod(_redeemRequest), "REDEEM_NOT_READY");

        (bool success, uint256 exchangeRate) = _getExchangeRateByUnlockTimestamp(_redeemRequest.requestTime);
        require(success, "EXCHANGE_RATE_NOT_FOUND");

        uint256 shareAmount = _redeemRequest.requestAmount;
        uint256 startedAt = _redeemRequest.requestTime;
        uint256 avaxAmount = (exchangeRate * shareAmount) / 1e18;

        require(avaxAmount >= shareAmount, "INVALID_EXCHANGE_RATE");

        lss.sharesDeposited[user] -= shareAmount;
        LibERC20._burn(address(this), shareAmount);

        lss.totalStakedAvax -= avaxAmount;

        lss.redeemRequest[user][redeemRequestIndex] = lss.redeemRequest[user][lss.redeemRequest[user].length - 1];
        lss.redeemRequest[user].pop();

        if (lss.redeemRequest[user].length == 0) {
            uint256 oldIndex = lss.redeemersIndex[user];
            address lastMember = lss.redeemers[lss.redeemers.length - 1];

            lss.redeemers[oldIndex] = lastMember;
            lss.redeemers.pop();

            lss.redeemersIndex[lastMember] = oldIndex;
            
            delete lss.redeemersIndex[user];
            
            delete lss.isRedeeming[user];
        }

        (success, ) = user.call{ value: avaxAmount }("");
        require(success, "AVAX_TRANSFER_FAILED");

        emit RedeemOwner(user, startedAt, shareAmount, avaxAmount);
    }

    /**
     * @notice Cancel an unexpired redeem request
     * @param redeemRequestIndex Index number of the cancelled redeem
     */
    function _cancelRedeemRequest(uint256 redeemRequestIndex) internal {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        address user = LibContext._msgSender();

        require(redeemRequestIndex < lss.redeemRequest[user].length, "INVALID_INDEX");

        LibLiquidStakingStorage.RedeemRequestStruct memory _redeemRequest = lss.redeemRequest[user][redeemRequestIndex];

        require(!_isExpired(_redeemRequest), "REDEEM_REQUEST_EXPIRED");

        uint256 shareAmount = _redeemRequest.requestAmount;
        uint256 redeemRequestedAt = _redeemRequest.requestTime;

        if (redeemRequestIndex != lss.redeemRequest[user].length - 1) {
            lss.redeemRequest[user][redeemRequestIndex] = lss.redeemRequest[user][lss.redeemRequest[user].length - 1];
        }

        lss.redeemRequest[user].pop();

        lss.sharesDeposited[user] -= shareAmount;
        LibERC20._transfer(address(this), user, shareAmount);

        if (lss.redeemRequest[user].length == 0) {
            uint256 oldIndex = lss.redeemersIndex[user];
            address lastMember = lss.redeemers[lss.redeemers.length - 1];

            lss.redeemers[oldIndex] = lastMember;
            lss.redeemers.pop();

            lss.redeemersIndex[lastMember] = oldIndex;
            
            delete lss.redeemersIndex[user];
            
            lss.isRedeeming[user] = false;
        }

        emit CancelRedeem(user, redeemRequestedAt, shareAmount);
    }

    /**
     * @notice Manage arbitrageurs request
     * @param arbitrageurs The arbitrageurs' address
     * @param user User being managed by the arbitrageurs
     * @param _redeemRequestUser User redeem request fulfilled by the arbitrageurs
     * @param _value AVAX value deposited by the arbitrageurs
     * @param _time Block.timestamp
     */
    function _manageArbitrageursRequest(address arbitrageurs, address user, LibLiquidStakingStorage.RedeemRequestStruct memory _redeemRequestUser, uint256 _value, uint256 _time) internal returns(bool) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();
 
        // Update balances
        lss.sharesDeposited[user] -= _redeemRequestUser.requestAmount;
        lss.sharesDeposited[arbitrageurs] += _redeemRequestUser.requestAmount;
        lss.arbitrageursRedeem[arbitrageurs].push(LibLiquidStakingStorage.ArbitrageursRedeemStruct(
            _time,
            _redeemRequestUser.requestAmount,
            0
        ));

        // Transfers AVAX value from arbitrageurs deposit to user
        (bool success, ) = user.call{ value: _value }("");
        require(success, "AVAX_TRANSFER_FAILED");

        return true;
    }
}