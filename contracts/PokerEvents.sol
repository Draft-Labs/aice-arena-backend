// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PokerEvents {
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

    // Error messages
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

    // HandRank enum needed for HandWinner event
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

    // Game state enum
    enum GameState {
        Idle,
        PreFlop,
        Flop,
        Turn,
        River,
        Showdown,
        HandComplete
    }

    // Game state change event
    event GameStateChanged(uint256 indexed tableId, uint8 newState);
}
