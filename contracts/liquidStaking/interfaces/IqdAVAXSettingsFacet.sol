// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IqdAVAXSettingsFacet {
    /// @notice Emitted when setted a pause on minting
    event pauseMinting(uint256 indexed time, bool pause);
    /// @notice Emitted when setted a pause on redeeming
    event pauseRedeeming(uint256 indexed time, bool pause);
    /// @notice Emitted when setted a pause period on minting
    event pausePeriodMinting(uint256 indexed period, uint256 endPeriod, uint256 time);
    /// @notice Emitted when setted a pause period on redeeming
    event pausePeriodRedeeming(uint256 indexed period, uint256 endPeriod, uint256 time);
    /// @notice Emitted when deposited AVAX in the contract
    event avaxDeposited(uint256 indexed deposit, address manager, uint256 time);
    /// @notice Emitted when withdrawn AVAX from the contract
    event avaxWithdrawn(uint256 indexed withdraw, address manager, uint256 time);
    /// @notice Emitted when accured rewards
    event rewardsDeposit(uint256 indexed newStakedAvax, uint256 indexed oldStakedAvax, uint256 time);
    /// @notice Emitted when changed cooldown period
    event settedCooldownPeriod(uint256 indexed newPeriod, uint256 indexed oldPeriod, uint256 time);
    /// @notice Emitted when changed redeem period
    event settedRedeemPeriod(uint256 indexed newPeriod, uint256 indexed oldPeriod, uint256 time);
    /// @notice Emitted when changed max staked avax
    event settedMaxStakedAvax(uint256 indexed newMaxStakedAvax, uint256 indexed oldMaxStakedAvax, uint256 time);
    /// @notice Emitted when changed LP fees
    event settedLPfees(uint256[] indexes, uint256[] fees, uint256 time);
    /// @notice Emitted when changed LP vesting periods
    event settedLPVestingPeriods(uint256[] indexes, uint256[] periods, uint256 time);

}