// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IqdAVAX {
    /// @notice Emitted when user deposit and mint successfully
    event newShares(address indexed sender, uint256 indexed value, uint256 shares);
    /// @notice Emitted when someone makes a request to redeem
    event redeemRequest(address indexed sender, uint256 indexed shares, uint256 time);
    /// @notice Emitted when someone withdraw qdAVAX from expired requests
    event RedeemExpiredShares(address indexed user, uint256 shares);
    /// @notice Emitted when abritrageur fulfill a redeem request
    event ArbitrageurFulfilledRequest(address indexed arbitrageurs, address indexed user, uint256 sharesAmount, uint256 valueAmount, uint256 time);
    /// @notice Emitted when abritrageur withdraw vested tokens
    event ArbitrageurWithdrawRequest(address indexed arbitrageurs, uint256 requestIndex, uint256 withdrawAmount, uint256 withdrawRemeaning, uint256 _time);
}