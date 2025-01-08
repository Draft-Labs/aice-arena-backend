// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IPokerTable.sol";
import "./PokerHandEvaluator.sol";

/**
 * @title PokerGameState
 * @dev Contract for managing poker game state progression
 */
contract PokerGameState is Ownable {
    using PokerHandEvaluator for *;

    IPokerTable public pokerTable;

    // Events
    event GameStarted(uint256 indexed tableId);
    event HandDealt(uint256 indexed tableId);
    event FlopDealt(uint256 indexed tableId);
    event TurnDealt(uint256 indexed tableId);
    event RiverDealt(uint256 indexed tableId);
    event ShowdownStarted(uint256 indexed tableId);
    event HandComplete(uint256 indexed tableId, address indexed winner, uint256 amount);

    // Error messages
    error InvalidGameState();
    error NotEnoughPlayers();
    error PlayerNotFound();
    error NotAuthorized();
    error InvalidAction();

    constructor(address _pokerTableAddress) Ownable(msg.sender) {
        pokerTable = IPokerTable(_pokerTableAddress);
    }

    /**
     * @dev Updates the PokerTable contract address
     */
    function setPokerTable(address _pokerTableAddress) external onlyOwner {
        require(_pokerTableAddress != address(0), "Invalid address");
        pokerTable = IPokerTable(_pokerTableAddress);
    }

    /**
     * @dev Starts a new game at the table
     */
    function startGame(uint256 tableId) external {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();

        // Get table info
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Validate game state
        if (gameState != IPokerTable.GameState.Waiting) revert InvalidGameState();

        // Check number of players
        address[] memory players = pokerTable.getTablePlayers(tableId);
        if (players.length < 2) revert NotEnoughPlayers();

        // Set game state to PreFlop
        bool success = pokerTable.updateGameState(tableId, IPokerTable.GameState.PreFlop);
        if (!success) revert InvalidAction();

        emit GameStarted(tableId);
    }

    /**
     * @dev Deals hole cards to players
     */
    function dealHoleCards(uint256 tableId) external {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();

        // Get table info
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Validate game state
        if (gameState != IPokerTable.GameState.PreFlop) revert InvalidGameState();

        // Deal cards to players
        // This would be handled by the VRF system in practice
        bool success = pokerTable.dealCards(tableId);
        if (!success) revert InvalidAction();

        emit HandDealt(tableId);
    }

    /**
     * @dev Deals the flop
     */
    function dealFlop(uint256 tableId) external {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();

        // Get table info
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Validate game state
        if (gameState != IPokerTable.GameState.PreFlop) revert InvalidGameState();

        // Deal flop
        bool success = pokerTable.dealFlop(tableId);
        if (!success) revert InvalidAction();

        // Update game state
        success = pokerTable.updateGameState(tableId, IPokerTable.GameState.Flop);
        if (!success) revert InvalidAction();

        emit FlopDealt(tableId);
    }

    /**
     * @dev Deals the turn
     */
    function dealTurn(uint256 tableId) external {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();

        // Get table info
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Validate game state
        if (gameState != IPokerTable.GameState.Flop) revert InvalidGameState();

        // Deal turn
        bool success = pokerTable.dealTurn(tableId);
        if (!success) revert InvalidAction();

        // Update game state
        success = pokerTable.updateGameState(tableId, IPokerTable.GameState.Turn);
        if (!success) revert InvalidAction();

        emit TurnDealt(tableId);
    }

    /**
     * @dev Deals the river
     */
    function dealRiver(uint256 tableId) external {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();

        // Get table info
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Validate game state
        if (gameState != IPokerTable.GameState.Turn) revert InvalidGameState();

        // Deal river
        bool success = pokerTable.dealRiver(tableId);
        if (!success) revert InvalidAction();

        // Update game state
        success = pokerTable.updateGameState(tableId, IPokerTable.GameState.River);
        if (!success) revert InvalidAction();

        emit RiverDealt(tableId);
    }

    /**
     * @dev Initiates the showdown
     */
    function startShowdown(uint256 tableId) external {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();

        // Get table info
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Validate game state
        if (gameState != IPokerTable.GameState.River) revert InvalidGameState();

        // Update game state
        bool success = pokerTable.updateGameState(tableId, IPokerTable.GameState.Showdown);
        if (!success) revert InvalidAction();

        emit ShowdownStarted(tableId);
    }

    /**
     * @dev Determines the winner and awards the pot
     */
    function determineWinner(uint256 tableId) external {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();

        // Get table info
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 pot,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Validate game state
        if (gameState != IPokerTable.GameState.Showdown) revert InvalidGameState();

        // Get active players and their hands
        address[] memory players = pokerTable.getTablePlayers(tableId);
        address winner = address(0);
        PokerHandEvaluator.HandResult memory bestHand;

        for (uint256 i = 0; i < players.length; i++) {
            (,, bool isActive,, bool inHand) = pokerTable.getPlayerInfo(tableId, players[i]);
            if (isActive && inHand) {
                // Get player's hand and evaluate it
                (PokerHandEvaluator.Card[] memory holeCards,) = pokerTable.getPlayerCards(tableId, players[i]);
                PokerHandEvaluator.Card[] memory communityCards = pokerTable.getCommunityCards(tableId);
                PokerHandEvaluator.HandResult memory currentHand = PokerHandEvaluator.evaluateHand(holeCards, communityCards);

                // Compare with best hand so far
                if (winner == address(0) || PokerHandEvaluator.compareHands(currentHand, bestHand)) {
                    winner = players[i];
                    bestHand = currentHand;
                }
            }
        }

        // Award pot to winner
        bool success = pokerTable.awardPotToPlayer(tableId, winner, pot);
        if (!success) revert InvalidAction();

        // Reset game state
        success = pokerTable.updateGameState(tableId, IPokerTable.GameState.Waiting);
        if (!success) revert InvalidAction();

        emit HandComplete(tableId, winner, pot);
    }

    /**
     * @dev Checks if all players have acted and betting round is complete
     */
    function isBettingRoundComplete(uint256 tableId) external view returns (bool) {
        address[] memory players = pokerTable.getTablePlayers(tableId);
        uint256 activePlayerCount = 0;
        uint256 actedPlayerCount = 0;
        uint256 currentBet = 0;

        for (uint256 i = 0; i < players.length; i++) {
            (uint256 stake, uint256 bet, bool isActive,, bool inHand) = pokerTable.getPlayerInfo(tableId, players[i]);
            if (isActive && inHand) {
                activePlayerCount++;
                if (bet == currentBet || stake == 0) {
                    actedPlayerCount++;
                }
                if (bet > currentBet) {
                    currentBet = bet;
                    actedPlayerCount = 1;
                }
            }
        }

        return activePlayerCount > 0 && actedPlayerCount == activePlayerCount;
    }

    /**
     * @dev Checks if only one player remains active
     */
    function isOnePlayerRemaining(uint256 tableId) external view returns (bool) {
        address[] memory players = pokerTable.getTablePlayers(tableId);
        uint256 activePlayerCount = 0;

        for (uint256 i = 0; i < players.length; i++) {
            (,, bool isActive,, bool inHand) = pokerTable.getPlayerInfo(tableId, players[i]);
            if (isActive && inHand) {
                activePlayerCount++;
                if (activePlayerCount > 1) return false;
            }
        }

        return activePlayerCount == 1;
    }
} 