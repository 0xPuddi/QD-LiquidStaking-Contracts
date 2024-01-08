// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Utility contract for preventing reentrancy attacks
 */
abstract contract LibReentrancyGuard {
    modifier nonReentrant() {
        LibReentrancyGuardStorage.Layout storage l = LibReentrancyGuardStorage
            .layout();
        require(l.status != 2, 'ReentrancyGuard: reentrant call');
        l.status = 2;
        _;
        l.status = 1;
    }
}

/**
 * @notice Reentrancy library to point storage slot
 */
library LibReentrancyGuardStorage {
    struct Layout {
        uint256 status;
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256('solidstate.contracts.storage.LibReentrancyGuard');

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}


