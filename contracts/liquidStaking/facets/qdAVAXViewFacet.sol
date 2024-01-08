// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibLiquidStakingStorage } from "../libraries/LibLiquidStakingStorage.sol";
import { LibqdAVAXFacet } from "../libraries/LibqdAVAXFacet.sol";

/**
 * QuarryDraw Staked AVAX view contract.
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
contract qdAVAXViewFacet {
    /**
     * @return The amount of AVAX that represets the amount of token shares
     * according to AVAX controlled by the protocol.
     */
    function getStakedAvaxByShares(uint256 _shareAmount) external view returns(uint256) {
        return LibqdAVAXFacet._getStakedAvaxByShares(_shareAmount);
    }

    /**
     * @notice Get redeemers array
     */
    function getRedeemersArray() external view returns(address[] memory) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();
        return lss.redeemers;
    }

    /**
     * @notice Get redeemer redeems number
     */
    function getRedeemerRedeemsNumber(address _user) external view returns(uint256) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();
        return lss.redeemRequest[_user].length;
    }

    /**
     * @notice Get redeemer redeems
     */
    function getRedeemerRedeemInfo(address _user, uint256 _index) external view returns(LibLiquidStakingStorage.RedeemRequestStruct memory, uint256, LibLiquidStakingStorage.exchangeRatePeriod) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        LibLiquidStakingStorage.RedeemRequestStruct memory _redeemRequest = lss.redeemRequest[_user][_index];
        uint256 exchangeRate;
        LibLiquidStakingStorage.exchangeRatePeriod _exchangeRatePeriod;

        if (LibqdAVAXFacet._isWithinRedeemPeriod(_redeemRequest)) {
            (bool success, uint256 _exchangeRate) = LibqdAVAXFacet._getExchangeRateByUnlockTimestamp(_redeemRequest.requestTime);
            require(success, "EXCHANGE_RATE_NOT_FOUND");

            exchangeRate = _exchangeRate;

            _exchangeRatePeriod = LibLiquidStakingStorage.exchangeRatePeriod.RedeemPeriod;
        } else {
            exchangeRate = LibqdAVAXFacet._getStakedAvaxByShares(_redeemRequest.requestAmount);

            _exchangeRatePeriod = LibLiquidStakingStorage.exchangeRatePeriod.CooldownPeriod;
        }

        return (_redeemRequest, exchangeRate, _exchangeRatePeriod);
    }

    /**
     * @notice Get all redeemer redeems info - add exchange rates, add signal about the hour
     */
    function getRedeemerInfoFromTo(address _user, uint256 from, uint256 to) external view returns(LibLiquidStakingStorage.RedeemRequestStruct[] memory, uint256[] memory, LibLiquidStakingStorage.exchangeRatePeriod[] memory) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        LibLiquidStakingStorage.RedeemRequestStruct[] memory _allRedeemerRedeemInfo = lss.redeemRequest[_user];

        require(from < _allRedeemerRedeemInfo.length, "FROM_OUT_OF_BONDS");
        require(from < to, "FROM_GREATER_THAN_TO");

        if (to > _allRedeemerRedeemInfo.length) {
            to = _allRedeemerRedeemInfo.length;
        }

        LibLiquidStakingStorage.RedeemRequestStruct[] memory redeemerInfoFromTo = new LibLiquidStakingStorage.RedeemRequestStruct[](to - from);
        uint256[] memory _exchangeRates = new uint256[](to - from);
        LibLiquidStakingStorage.exchangeRatePeriod[] memory _exchangeRatePeriod = new LibLiquidStakingStorage.exchangeRatePeriod[](to - from);

        for (uint256 i = 0; i < to - from; ) {
            redeemerInfoFromTo[i] = _allRedeemerRedeemInfo[from + i];

            if (LibqdAVAXFacet._isWithinRedeemPeriod(redeemerInfoFromTo[i])) {
                (bool success, uint256 exchangeRate) = LibqdAVAXFacet._getExchangeRateByUnlockTimestamp(redeemerInfoFromTo[i].requestTime);
                require(success, "EXCHANGE_RATE_NOT_FOUND");

                _exchangeRates[i] = exchangeRate;

                _exchangeRatePeriod[i] = LibLiquidStakingStorage.exchangeRatePeriod.RedeemPeriod;
            } else {
                _exchangeRates[i] = LibqdAVAXFacet._getStakedAvaxByShares(1e18);

                _exchangeRatePeriod[i] = LibLiquidStakingStorage.exchangeRatePeriod.CooldownPeriod;
            }
            
            unchecked {
                ++i;
            }
        }

        return(redeemerInfoFromTo, _exchangeRates, _exchangeRatePeriod);
    }

    /**
     * @notice Get arbitrageur price
     * @param holderLevel Highest level of validator share owned by arbitrageurs
     * @param _redeemRequestUser User redeem request that arbitrageurs wants to fulfill
     */
    function getArbitrageurPrice(uint256 holderLevel, LibLiquidStakingStorage.RedeemRequestStruct memory _redeemRequestUser) external view returns(uint256) {
        return LibqdAVAXFacet._calculateArbitrageursPrice(holderLevel, _redeemRequestUser);
    }

    /**
     * @notice Get arbitrageurs' amount linear vesting completed
     */
    function getArbitrageursLinearVestingAmount(address arbitrageurs, uint256 holderLevel, uint256 requestIndex) external view returns(uint256, uint256, uint256) {
        return LibqdAVAXFacet._linearVestingArbitrageurs(arbitrageurs, holderLevel, requestIndex);
    }

    /**
     * @notice Get arbitrageurs info at index
     */
    function getArbitrageurInfo(address _arbitrageurs, uint256 _index) external view returns(uint256, uint256, uint256) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        require(lss.arbitrageursRedeem[_arbitrageurs].length > _index, 'INDEX_OUT_OF_BONDS_OR_NULL');

        LibLiquidStakingStorage.ArbitrageursRedeemStruct memory requestArbitrageur = lss.arbitrageursRedeem[_arbitrageurs][_index];

        require(requestArbitrageur.arbitrageTime > 0 && requestArbitrageur.arbitrageAmount > 0, "WRONG_INDEX_EMPTY_REQUEST");

        return(requestArbitrageur.arbitrageTime, requestArbitrageur.arbitrageAmount, requestArbitrageur.arbitrageAmountCollected);
    }

    /**
     * @notice Get arbitrageur info from index to index
     */
    function getArbitrageurInfoFromTo(address _arbitrageurs, uint256 from, uint256 to) external view returns(LibLiquidStakingStorage.ArbitrageursRedeemStruct[] memory) {
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();

        LibLiquidStakingStorage.ArbitrageursRedeemStruct[] memory requestArbitrageur = lss.arbitrageursRedeem[_arbitrageurs];

        require(from < requestArbitrageur.length, "FROM_OUT_OF_BONDS");
        require(from < to, "FROM_GREATER_THAN_TO");

        if (to > requestArbitrageur.length) {
            to = requestArbitrageur.length;
        }

        LibLiquidStakingStorage.ArbitrageursRedeemStruct[] memory requestArbitrageurFromTo = new LibLiquidStakingStorage.ArbitrageursRedeemStruct[](to - from);

        for (uint256 i = 0; i < to - from; ) {
            requestArbitrageurFromTo[i] = requestArbitrageur[from + i];
            
            unchecked {
                ++i;
            }
        }

        return(requestArbitrageurFromTo);
    }
}