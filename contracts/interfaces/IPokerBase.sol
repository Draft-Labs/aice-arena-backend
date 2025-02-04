// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPokerEvents.sol";

interface IPokerBase is IPokerEvents {
    // Enums
    enum HandRank {
        HighCard,
        Pair,
        TwoPair,
        ThreeOfAKind,
        Straight,
        Flush,
        FullHouse,
        FourOfAKind,
        StraightFlush,
        RoyalFlush
    }

    enum GameState {
        Waiting,    // Waiting for players
        Dealing,    // Cards being dealt
        PreFlop,    // Initial betting round
        Flop,       // After first 3 community cards
        Turn,       // After 4th community card
        River,      // After 5th community card
        Showdown,   // Revealing hands
        Complete    // Game finished
    }

    // Structs
    struct Player {
        address playerAddress;
        uint256 tableStake;     // Current chips at table
        uint256 currentBet;     // Current bet in the round
        bool isActive;          // Still in the current hand
        bool isSittingOut;      // Temporarily sitting out
        uint256 position;       // Position at table (0-5)
    }

    struct Table {
        uint256 tableId;
        uint256 minBuyIn;
        uint256 maxBuyIn;
        uint256 smallBlind;
        uint256 bigBlind;
        uint256 minBet;
        uint256 maxBet;
        uint256 pot;
        uint256 currentBet;
        uint256 dealerPosition;
        uint256 currentPosition;
        uint256 playerCount;
        GameState gameState;
        bool isActive;
    }

    // Events
    event TableCreated(uint256 indexed tableId, uint256 minBuyIn, uint256 maxBuyIn);
    event PlayerJoined(uint256 indexed tableId, address indexed player, uint256 buyIn);
    event PlayerLeft(uint256 indexed tableId, address indexed player, uint256 remainingStake);
    event GameStarted(uint256 indexed tableId);
    event BetPlaced(uint256 indexed tableId, address indexed player, uint256 amount);
    event PlayerFolded(uint256 indexed tableId, address indexed player);
    event HandComplete(uint256 indexed tableId, address indexed winner, uint256 pot);
    event TableConfigUpdated(
        uint256 indexed tableId,
        uint256 minBet,
        uint256 maxBet
    );
    event PlayerCardsDealt(uint256 indexed tableId, address indexed player, uint8[] cards);
    event CommunityCardsDealt(uint256 indexed tableId, uint8[] cards);
    event CardsDealt(uint256 indexed tableId, address indexed player, uint8[] cards);
    event BlindsPosted(uint256 indexed tableId, address smallBlind, address bigBlind, uint256 smallBlindAmount, uint256 bigBlindAmount);
    event HandWinner(uint256 indexed tableId, address indexed winner, HandRank winningHandRank, uint256 potAmount);
    event TurnStarted(uint256 indexed tableId, address indexed player);
    event TurnEnded(uint256 indexed tableId, address indexed player, string action);
    event RoundComplete(uint256 indexed tableId);

    // Errors
    error TableFull();
    error InvalidBuyIn();
    error PlayerNotAtTable();
    error InvalidBetAmount();
    error NotPlayerTurn();
    error InvalidGameState();
    error InsufficientBalance();
    error TableNotActive();
    error InvalidBetLimits();
    error OnlyOwnerAllowed();
} 