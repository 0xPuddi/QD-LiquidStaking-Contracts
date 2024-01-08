// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
*
* Implementation of a diamond.
/******************************************************************************/

import { LibLiquidStakingStorage } from "./libraries/LibLiquidStakingStorage.sol";

import {LibDiamond} from "../shared/libraries/LibDiamond.sol";
import { IDiamondLoupe } from "../shared/interfaces/IDiamondLoupe.sol";
import { IDiamondCut } from "../shared/interfaces/IDiamondCut.sol";
import { IERC173 } from "../shared/interfaces/IERC173.sol";
import { IERC165 } from "../shared/interfaces/IERC165.sol";
import { IERC1155 } from "../shared/interfaces/IERC1155.sol";
import { IERC20 } from "../shared/interfaces/IERC20.sol";

// It is expected that this contract is customized if you want to deploy your diamond
// with data from a deployment script. Use the init function to initialize state variables
// of your diamond. Add parameters to the init funciton if you need to.

contract DiamondInit {    
    // You can add parameters to this function in order to pass in 
    // data to set your own state variables
    function init(IERC1155 _avalancheValidatorAddress) external {
        // adding ERC165 data
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;
        ds.supportedInterfaces[type(IERC20).interfaceId] = true;

        // add your own state variables 
        // EIP-2535 specifies that the `diamondCut` function takes two optional 
        // arguments: address _init and bytes calldata _calldata
        // These arguments are used to execute an arbitrary function using delegatecall
        // in order to set state variables in the diamond during deployment or an upgrade
        // More info here: https://eips.ethereum.org/EIPS/eip-2535#diamond-interface

        // Retrive storage
        LibLiquidStakingStorage.lsStorage storage lss = LibLiquidStakingStorage.lsStoragePosition();
        // ERC20 costructor
        lss.ERC20.name = "QuarryDraw Staked AVAX";
        lss.ERC20.symbol = "qdAVAX";
        // ERC1155
        lss.IAvalancheValidators[0] = _avalancheValidatorAddress;
        // Avax
        lss.maxStakedAvax = type(uint).max; // give validator * 5 ?? could be good
        // Redeem
        lss.cooldownPeriod = 14 days;
        lss.redeemPeriod = 1 days;
        lss.LPfees[0] = 1e16; // 1%
        lss.LPfees[1] = 2e16; // 2%
        lss.LPfees[2] = 3e16; // 3%
        lss.LPfees[3] = 4e16; // 4%
        lss.LPfees[4] = 5e16; // 5%
        lss.LPVestingPeriods[0] = 9 days;
        lss.LPVestingPeriods[1] = 8 days;
        lss.LPVestingPeriods[2] = 7 days;
        lss.LPVestingPeriods[3] = 6 days;
        lss.LPVestingPeriods[4] = 5 days;
        // Utils
        lss.PERCENTAGE_PRECISION = 1e18;
    }
}