// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "./PokerMain.sol";

/**
 * @title Poker
 * @dev This contract is deprecated and exists only for backward compatibility.
 * Please use PokerMain contract for all new integrations.
 */
contract Poker is PokerMain {
    constructor(uint256 _minBetAmount, address payable _treasuryAddress) 
        PokerMain(_minBetAmount, _treasuryAddress) {}
}
