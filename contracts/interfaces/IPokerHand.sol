// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPokerBase.sol";

interface IPokerHand {
    // Card management
    function dealPlayerCards(uint256 tableId, address player, uint8[] calldata cards) external;
    function dealCommunityCards(uint256 tableId, uint8[] calldata cards) external;
    function getPlayerCards(uint256 tableId, address player) external view returns (uint8[] memory);
    function getCommunityCards(uint256 tableId) external view returns (uint8[] memory);

    // Hand evaluation
    function evaluateHand(uint8[] calldata cards) external pure returns (IPokerBase.HandRank rank, uint256 score);
    function determineWinner(uint256 tableId) external returns (address winner, IPokerBase.HandRank winningRank, uint256 winningScore);
    function compareHands(
        uint8[] calldata hand1,
        uint8[] calldata hand2
    ) external pure returns (int8); // Returns: 1 if hand1 wins, -1 if hand2 wins, 0 if tie

    // Card validation
    function isValidCard(uint8 card) external pure returns (bool);
    function isValidHand(uint8[] calldata cards) external pure returns (bool);
    function getCardRank(uint8 card) external pure returns (uint8);
    function getCardSuit(uint8 card) external pure returns (uint8);
} 