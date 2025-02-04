// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPokerEvents
 * @dev Optimized events interface for the poker game
 * Event optimizations:
 * 1. Reduced parameter sizes
 * 2. Combined related events
 * 3. Indexed important parameters
 */
interface IPokerEvents {
    // Table events - combined table management events
    event TableEvent(
        uint256 indexed tableId,
        uint8 indexed eventType,  // 0: Created, 1: Updated, 2: Closed
        uint40 minBuyIn,
        uint40 maxBuyIn,
        uint40 minBet,
        uint40 maxBet
    );

    // Player events - combined player-related events
    event PlayerEvent(
        uint256 indexed tableId,
        address indexed player,
        uint8 indexed eventType,  // 0: Joined, 1: Left, 2: SitOut, 3: SitIn
        uint40 amount            // buyIn/remainingStake amount
    );

    // Game action events - combined betting and action events
    event GameAction(
        uint256 indexed tableId,
        address indexed player,
        uint8 indexed actionType,  // 0: Bet, 1: Call, 2: Raise, 3: Check, 4: Fold
        uint40 amount,            // bet/raise amount
        uint40 potSize           // current pot size after action
    );

    // Round events - combined round state events
    event RoundState(
        uint256 indexed tableId,
        uint8 indexed roundType,  // 0: PreFlop, 1: Flop, 2: Turn, 3: River, 4: Showdown
        uint40 potSize,
        uint8 activePlayerCount
    );

    // Card events - combined card dealing events
    event CardsDealt(
        uint256 indexed tableId,
        address indexed player,   // address(0) for community cards
        uint8[] cards,
        uint8 cardType           // 0: Player cards, 1: Flop, 2: Turn, 3: River
    );

    // Game result event - optimized winner event
    event GameResult(
        uint256 indexed tableId,
        address indexed winner,
        uint8 handRank,          // 0-9 for different hand ranks
        uint40 winAmount,
        uint40 finalPot
    );

    // Blind posting event - optimized blind event
    event BlindsPosted(
        uint256 indexed tableId,
        address indexed smallBlind,
        address indexed bigBlind,
        uint40 smallBlindAmount,
        uint40 bigBlindAmount
    );
} 