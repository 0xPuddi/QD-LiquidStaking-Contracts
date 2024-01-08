// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibLiquidStakingStorage } from "../libraries/LibLiquidStakingStorage.sol";
import { LibqdAVAXFacet } from "../libraries/LibqdAVAXFacet.sol";
import { IqdAVAXSettingsFacet } from "../interfaces/IqdAVAXSettingsFacet.sol";

import {LibDiamond} from "../../shared/libraries/LibDiamond.sol";
import { LibContext } from "../../shared/libraries/LibContext.sol";

contract qdAVAXSettingsFacet is IqdAVAXSettingsFacet {
    /// Set undefined mint pause
    function setMintPause(bool _pause) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        lss.pauseMint = _pause;

        emit pauseMinting(block.timestamp, _pause);
    }

    /// Set mint pause period
    function setMintPausePeriod(uint256 _pause) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        lss.timePauseMint = block.timestamp + _pause;

        emit pausePeriodMinting(_pause, block.timestamp + _pause, block.timestamp);
    }

    /// Set undefined redeem pause
    function setRedeemPause(bool _pause) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        lss.pauseRedeem = _pause;

        emit pauseRedeeming(block.timestamp, _pause);
    }

    /// Set redeem pause period
    function setRedeemPausePeriod(uint256 _pause) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        lss.timePauseMint = block.timestamp + _pause;

        emit pausePeriodRedeeming(_pause, block.timestamp + _pause, block.timestamp);
    }

    /// Set maxStakedAvax
    function setMaxStakedAvax(uint256 newMaxStakedAvax) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256 oldMaxStakedAvax = lss.maxStakedAvax;
        lss.maxStakedAvax = newMaxStakedAvax;

        emit settedMaxStakedAvax(newMaxStakedAvax, oldMaxStakedAvax, block.timestamp);
    } 

    /// Set redeemPeriod
    function setRedeemPeriod(uint256 newRedeemPeriod) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256 oldRedeemPeriod = lss.redeemPeriod;
        lss.redeemPeriod = newRedeemPeriod;

        emit settedRedeemPeriod(newRedeemPeriod, oldRedeemPeriod, block.timestamp);
    }

    /// Set cooldownPeriod
    function setCooldownPeriod(uint256 newCooldownPeriod) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256 oldCooldownPeriod = lss.cooldownPeriod;
        lss.cooldownPeriod = newCooldownPeriod;

        emit settedCooldownPeriod(newCooldownPeriod, oldCooldownPeriod, block.timestamp);
    }

    /// Set LP vesting periods
    function setLPVestingPeriods(uint256[] calldata indexes, uint256[] calldata periods) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        require(periods.length == indexes.length, "INVALID_COMPOSITION");

        for (uint256 i = 0; i < periods.length; ) {
            lss.LPVestingPeriods[indexes[i]] = periods[i];
            unchecked {
                ++i;
            }
        }

        emit settedLPVestingPeriods(indexes, periods, block.timestamp);
    }

    /// Set LP fees
    function setLPfees(uint256[] calldata indexes, uint256[] calldata fees) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        require(fees.length == indexes.length, "INVALID_COMPOSITION");

        for (uint256 i = 0; i < fees.length; ) {
            lss.LPfees[indexes[i]] = fees[i];
            unchecked {
                ++i;
            }
        }

        emit settedLPfees(indexes, fees, block.timestamp);
    }

    /// Deposit AVAX into the contract, no token mint
    function depositAvaxToContract() external payable {
        LibDiamond.enforceIsContractOwner();

        require(msg.value > 0, "NO_DEPOSIT");

        emit avaxDeposited(msg.value, msg.sender, block.timestamp);
    } 

    /// Withdraw AVAX for delegation
    function withdrawAvaxFromContract(uint256 amount) external {
        LibDiamond.enforceIsContractOwner();

        require(amount > 0 && amount <= address(this).balance, "INVALID_WITHDRAW");

        address sender = LibContext._msgSender();
        (bool success, ) = sender.call{ value: amount }("");
        require(success, "AVAX_TRANSFER_FAILED");

        emit avaxWithdrawn(amount, sender, block.timestamp);
    } 

    /// Accure rewards qdAVAX
    function depositRewards(uint256 amountInWei) external {
        LibDiamond.enforceIsContractOwner();

        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        uint256 oldStakedAvax = lss.totalStakedAvax;
        lss.totalStakedAvax += amountInWei;

        LibqdAVAXFacet._dropExpiredExchangeRateEntries();
        lss.exchangeRatesByTimestamp[block.timestamp] = LibqdAVAXFacet._getStakedAvaxByShares(1e18);
        lss.timestampsExchangeRates.push(block.timestamp);

        emit rewardsDeposit(amountInWei, oldStakedAvax, block.timestamp);
    }
}