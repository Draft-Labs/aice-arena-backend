// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

interface IPokerTables {
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

    struct Player {
        address playerAddress;
        uint256 tableStake;     // Current chips at table
        uint256 currentBet;     // Current bet in the round
        bool isActive;          // Still in the current hand
        bool isSittingOut;      // Temporarily sitting out
        uint256 position;       // Position at table (0-5)
    }

    // External functions
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet
    ) external returns (uint256);

    function joinTable(uint256 tableId, uint256 buyInAmount) external;
    
    function leaveTable(uint256 tableId) external;
    
    function updateTableBetLimits(
        uint256 tableId,
        uint256 newMinBet,
        uint256 newMaxBet
    ) external;

    // View functions
    function getTableInfo(uint256 tableId) external view returns (
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet,
        uint256 pot,
        uint256 playerCount,
        GameState gameState,
        bool isActive
    );

    function getPlayerInfo(uint256 tableId, address player) external view returns (
        uint256 tableStake,
        uint256 currentBet,
        bool isActive,
        bool isSittingOut,
        uint256 position
    );

    function getTablePlayers(uint256 tableId) external view returns (address[] memory);
} 