// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import { IERC1155 } from "../../shared/interfaces/IERC1155.sol";

library LibLiquidStakingStorage {
    // Storage position
    bytes32 constant LIQUID_STAKING_STORAGE_POSITION = keccak256("liquid.staking.storage.position");

    // Enum exchange rate period - CooldownPeriod == 0, RedeemPeriod == 1
    enum exchangeRatePeriod { CooldownPeriod, RedeemPeriod }

    // ERC20 storage sruct
    struct ERC20Struct {
        // number of qdAVAX shares owned by an address
        mapping(address => uint256) balances;
        // allowance of token
        mapping(address => mapping(address => uint256)) allowances;
        // number of shares circulating
        uint256 totalSupply;
        // name ad symbol of shares
        string name;
        string symbol;
    }

    // Redeem request struct
    struct RedeemRequestStruct {
        // Time of the request
        uint256 requestTime;
        // Amount request
        uint256 requestAmount;
    }

    // Arbitrageurs redeem struct
    struct ArbitrageursRedeemStruct {
        // Time of arbitrage
        uint256 arbitrageTime;
        // Amount arbitrage
        uint256 arbitrageAmount;
        // Amount collected
        uint256 arbitrageAmountCollected;
    }

    // Storage struct
    struct lsStorage {
        /**
         * ERC20
         */
        // ERC20Struct declaration
        ERC20Struct ERC20;
        // Holders
        uint256 holders;

        /**
         * ERC1155 QuarryDraw Avalanche Validators
         */ 
        mapping(uint256 => IERC1155) IAvalancheValidators;

        /**
         * AVAX 
         */
        // Total AVAX deposited in the contract and in custody of QD
        uint256 totalStakedAvax;
        // Max AVAX amout that can be deposited in the contract and in custody of QD
        uint256 maxStakedAvax;
        // Total qdAVAX deposited by user in the cotract
        mapping(address => uint256) sharesDeposited;
        // Exchange rates by timestamps
        mapping(uint256 => uint256) exchangeRatesByTimestamp;
        // Timestamps array
        uint256[] timestampsExchangeRates;

        /**
         * Redeeming
         */
        // Redeem request mapping
        mapping(address => RedeemRequestStruct[]) redeemRequest;
        // Bool under redeem
        mapping(address => bool) isRedeeming;
        // Redeemers array
        address[] redeemers;
        // Redeemers array index
        mapping(address => uint256) redeemersIndex;
        // Cooldown period
        uint256 cooldownPeriod;
        // Redeem period
        uint256 redeemPeriod;
        // Mapping from holder ID to liquidity providers fee
        mapping(uint256 => uint256) LPfees;
        // Mapping from holder ID to vesting period of LPs
        mapping(uint256 => uint256) LPVestingPeriods;
        // Arbitrageurs redeem mapping
        mapping(address => ArbitrageursRedeemStruct[]) arbitrageursRedeem;

        /**
         * Pause
         */
        // Undefinited pause
        bool pauseMint;
        bool pauseRedeem;
        // Defined pause
        uint256 timePauseMint;
        uint256 timePauseRedeem;

        /**
         * Utils
         */
        // Percentage precision - 1e18
        uint256 PERCENTAGE_PRECISION;
    }

    // Retrive storage position
    function lsStoragePosition() internal pure returns (lsStorage storage lss) {
        bytes32 position = LIQUID_STAKING_STORAGE_POSITION;
        assembly {
            lss.slot := position
        }
    }

    /**
     * Utils functions
     */
    // Check mint pause
    function mintPaused() internal view {
        lsStorage storage lss = lsStoragePosition();

        require(!lss.pauseMint, "UNDEFINED_PAUSE");

        require(!(block.timestamp < lss.timePauseMint), "TIME_PAUSE");
    }

    // Check redeem pause
    function redeemPause() internal view {
        lsStorage storage lss = lsStoragePosition();

        require(!lss.pauseRedeem, "UNDEFINED_PAUSE");

        require(!(block.timestamp < lss.timePauseRedeem), "TIME_PAUSE");
    }
}