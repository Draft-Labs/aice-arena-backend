// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PokerHandEvaluator.sol";

/**
 * @title IPokerTable
 * @dev Interface for PokerTable contract that defines all required functionality
 */
interface IPokerTable {
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

    // Events
    event TableCreated(uint256 indexed tableId, uint256 minBuyIn, uint256 maxBuyIn);
    event PlayerJoined(uint256 indexed tableId, address indexed player, uint256 buyIn);
    event PlayerLeft(uint256 indexed tableId, address indexed player);
    event GameStarted(uint256 indexed tableId);
    event HandDealt(uint256 indexed tableId);
    event FlopDealt(uint256 indexed tableId);
    event TurnDealt(uint256 indexed tableId);
    event RiverDealt(uint256 indexed tableId);
    event BetPlaced(uint256 indexed tableId, address indexed player, uint256 amount);
    event PotAwarded(uint256 indexed tableId, address indexed winner, uint256 amount);
    event GameStateChanged(uint256 indexed tableId, GameState newState);

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
        GameState gameState
    );

    function getPlayerInfo(uint256 tableId, address player) external view returns (
        uint256 tableStake,
        uint256 currentBet,
        bool isActive,
        bool isSittingOut,
        bool inHand
    );

    function getTablePlayers(uint256 tableId) external view returns (address[] memory);

    function getPlayerCards(uint256 tableId, address player) external view returns (
        PokerHandEvaluator.Card[] memory holeCards,
        bool isRevealed
    );

    function getCommunityCards(uint256 tableId) external view returns (PokerHandEvaluator.Card[] memory);

    function isValidPlayer(uint256 tableId, address player) external view returns (bool);

    function isPlayerTurn(uint256 tableId, address player) external view returns (bool);

    // State-modifying functions
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind
    ) external returns (uint256);

    function addPlayer(
        uint256 tableId,
        address player,
        uint256 buyIn
    ) external returns (bool);

    function removePlayer(
        uint256 tableId,
        address player
    ) external returns (bool);

    function updatePlayerBet(
        uint256 tableId,
        address player,
        uint256 betAmount,
        uint256 newStake
    ) external returns (bool);

    function updatePlayerStake(
        uint256 tableId,
        address player,
        uint256 newStake
    ) external returns (bool);

    function updatePot(uint256 tableId, uint256 amount) external returns (bool);

    function awardPotToPlayer(
        uint256 tableId,
        address winner,
        uint256 amount
    ) external returns (bool);

    function advanceToNextPlayer(uint256 tableId) external returns (bool);

    function updateGameState(
        uint256 tableId,
        GameState newState
    ) external returns (bool);

    // Card dealing functions
    function dealCards(uint256 tableId) external returns (bool);
    function dealFlop(uint256 tableId) external returns (bool);
    function dealTurn(uint256 tableId) external returns (bool);
    function dealRiver(uint256 tableId) external returns (bool);

    // Game state functions
    function startGame(uint256 tableId) external returns (bool);
    function endGame(uint256 tableId) external returns (bool);
    function fold(uint256 tableId, address player) external returns (bool);
    function check(uint256 tableId, address player) external returns (bool);
    function call(uint256 tableId, address player) external returns (bool);
    function raise(uint256 tableId, address player, uint256 amount) external returns (bool);

    // Player action functions
    function updateCurrentPlayer(uint256 tableId, address player) external returns (bool);
} 