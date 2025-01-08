// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IPokerTable.sol";
import "./PokerHandEvaluator.sol";
import "./PokerBetting.sol";
import "./PokerPlayerManager.sol";
import "./PokerGameState.sol";
import "./PokerTreasury.sol";

/**
 * @title PokerTable
 * @dev Main contract for managing poker tables and game flow
 */
contract PokerTable is IPokerTable, Ownable, ReentrancyGuard {
    using PokerHandEvaluator for *;

    // Structs
    struct Table {
        uint256 minBuyIn;
        uint256 maxBuyIn;
        uint256 smallBlind;
        uint256 bigBlind;
        uint256 minBet;
        uint256 maxBet;
        uint256 pot;
        uint256 playerCount;
        GameState gameState;
        bool isActive;
        mapping(address => Player) players;
        address[] playerAddresses;
        address currentPlayer;
        PokerHandEvaluator.Card[] communityCards;
    }

    struct Player {
        uint256 tableStake;
        uint256 currentBet;
        bool isActive;
        bool isSittingOut;
        bool inHand;
        PokerHandEvaluator.Card[] holeCards;
        bool cardsRevealed;
    }

    // State variables
    mapping(uint256 => Table) private tables;
    uint256 private nextTableId;

    // Contract references
    PokerBetting public bettingContract;
    PokerPlayerManager public playerManager;
    PokerGameState public gameState;
    PokerTreasury public treasury;

    // Error messages
    error TableNotFound();
    error InvalidAmount();
    error PlayerNotFound();
    error InvalidGameState();
    error NotAuthorized();
    error TableFull();
    error InsufficientPlayers();

    constructor(
        address payable _bettingContract,
        address payable _playerManager,
        address payable _gameState,
        address payable _treasury
    ) Ownable(msg.sender) {
        bettingContract = PokerBetting(_bettingContract);
        playerManager = PokerPlayerManager(_playerManager);
        gameState = PokerGameState(_gameState);
        treasury = PokerTreasury(_treasury);
    }

    // Table management functions
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind
    ) external override onlyOwner returns (uint256) {
        if (minBuyIn == 0 || maxBuyIn == 0 || smallBlind == 0 || bigBlind == 0) revert InvalidAmount();
        if (minBuyIn >= maxBuyIn || smallBlind >= bigBlind) revert InvalidAmount();

        uint256 tableId = nextTableId++;
        Table storage newTable = tables[tableId];
        
        newTable.minBuyIn = minBuyIn;
        newTable.maxBuyIn = maxBuyIn;
        newTable.smallBlind = smallBlind;
        newTable.bigBlind = bigBlind;
        newTable.minBet = smallBlind;
        newTable.maxBet = maxBuyIn;
        newTable.gameState = GameState.Waiting;
        newTable.isActive = true;

        emit TableCreated(tableId, minBuyIn, maxBuyIn);
        return tableId;
    }

    function addPlayer(
        uint256 tableId,
        address player,
        uint256 buyIn
    ) external override returns (bool) {
        if (msg.sender != address(playerManager)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();
        if (table.playerCount >= 9) revert TableFull();
        if (buyIn < table.minBuyIn || buyIn > table.maxBuyIn) revert InvalidAmount();

        Player storage newPlayer = table.players[player];
        if (newPlayer.isActive) revert PlayerNotFound();

        newPlayer.tableStake = buyIn;
        newPlayer.isActive = true;
        newPlayer.inHand = false;
        table.playerAddresses.push(player);
        table.playerCount++;

        emit PlayerJoined(tableId, player, buyIn);
        return true;
    }

    function removePlayer(
        uint256 tableId,
        address player
    ) external override returns (bool) {
        if (msg.sender != address(playerManager)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        Player storage playerData = table.players[player];
        
        if (!table.isActive) revert TableNotFound();
        if (!playerData.isActive) revert PlayerNotFound();
        if (playerData.inHand) revert InvalidGameState();

        // Remove player from addresses array
        for (uint256 i = 0; i < table.playerAddresses.length; i++) {
            if (table.playerAddresses[i] == player) {
                    table.playerAddresses[i] = table.playerAddresses[table.playerAddresses.length - 1];
                table.playerAddresses.pop();
                break;
            }
        }
        
        playerData.isActive = false;
        table.playerCount--;

        emit PlayerLeft(tableId, player);
        return true;
    }

    // View functions
    function getTableInfo(uint256 tableId) external view override returns (
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet,
        uint256 pot,
        uint256 playerCount,
        GameState currentState
    ) {
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();

        return (
            table.minBuyIn,
            table.maxBuyIn,
            table.smallBlind,
            table.bigBlind,
            table.minBet,
            table.maxBet,
            table.pot,
            table.playerCount,
            table.gameState
        );
    }

    function getPlayerInfo(uint256 tableId, address player) external view override returns (
        uint256 tableStake,
        uint256 currentBet,
        bool isActive,
        bool isSittingOut,
        bool inHand
    ) {
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();

        Player storage playerData = table.players[player];
        return (
            playerData.tableStake,
            playerData.currentBet,
            playerData.isActive,
            playerData.isSittingOut,
            playerData.inHand
        );
    }

    function getTablePlayers(uint256 tableId) external view override returns (address[] memory) {
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();
        return table.playerAddresses;
    }

    function isValidPlayer(uint256 tableId, address player) external view override returns (bool) {
        Table storage table = tables[tableId];
        return table.isActive && table.players[player].isActive;
    }

    function isPlayerTurn(uint256 tableId, address player) external view override returns (bool) {
        Table storage table = tables[tableId];
        return table.isActive && table.currentPlayer == player;
    }

    // Card management functions
    function getPlayerCards(uint256 tableId, address player) external view override returns (
        PokerHandEvaluator.Card[] memory holeCards,
        bool isRevealed
    ) {
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();

        Player storage playerData = table.players[player];
        if (!playerData.isActive) revert PlayerNotFound();

        return (playerData.holeCards, playerData.cardsRevealed);
    }

    function getCommunityCards(uint256 tableId) external view override returns (PokerHandEvaluator.Card[] memory) {
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();
        return table.communityCards;
    }

    // Game state management functions
    function updateGameState(
        uint256 tableId,
        GameState newState
    ) external override returns (bool) {
        if (msg.sender != address(gameState)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();

        table.gameState = newState;
        emit GameStateChanged(tableId, newState);
        return true;
    }

    function startGame(uint256 tableId) external override returns (bool) {
        if (msg.sender != address(gameState)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();
        if (table.gameState != GameState.Waiting) revert InvalidGameState();
        if (table.playerCount < 2) revert InsufficientPlayers();

        // Reset game state
        delete table.communityCards;
        table.gameState = GameState.PreFlop;
        
        // Set all active players as in hand
        for (uint256 i = 0; i < table.playerAddresses.length; i++) {
            Player storage player = table.players[table.playerAddresses[i]];
            if (player.isActive && !player.isSittingOut) {
                player.inHand = true;
                player.currentBet = 0;
                player.cardsRevealed = false;
                delete player.holeCards;
            }
        }

        // Set first player
        table.currentPlayer = table.playerAddresses[0];

        emit GameStarted(tableId);
        return true;
    }

    function endGame(uint256 tableId) external override returns (bool) {
        if (msg.sender != address(gameState)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();

        // Reset game state
        delete table.communityCards;
        table.gameState = GameState.Waiting;
        table.pot = 0;
        
        // Reset player states
        for (uint256 i = 0; i < table.playerAddresses.length; i++) {
            Player storage player = table.players[table.playerAddresses[i]];
            if (player.isActive) {
                player.inHand = false;
                player.currentBet = 0;
                player.cardsRevealed = false;
                delete player.holeCards;
            }
        }

        return true;
    }

    // Card dealing functions
    function dealCards(uint256 tableId) external override returns (bool) {
        if (msg.sender != address(gameState)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();
        if (table.gameState != GameState.PreFlop) revert InvalidGameState();

        // In a real implementation, this would use Chainlink VRF
        // For now, just deal dummy cards
        for (uint256 i = 0; i < table.playerAddresses.length; i++) {
            Player storage player = table.players[table.playerAddresses[i]];
            if (player.isActive && player.inHand) {
                player.holeCards = new PokerHandEvaluator.Card[](2);
                player.holeCards[0] = PokerHandEvaluator.Card(uint8(i % 4), uint8(2 + (i * 2) % 13));
                player.holeCards[1] = PokerHandEvaluator.Card(uint8((i + 1) % 4), uint8(3 + (i * 2) % 13));
            }
        }

        emit HandDealt(tableId);
        return true;
    }

    function dealFlop(uint256 tableId) external override returns (bool) {
        if (msg.sender != address(gameState)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();
        if (table.gameState != GameState.PreFlop) revert InvalidGameState();

        // Deal 3 flop cards
        table.communityCards = new PokerHandEvaluator.Card[](3);
        table.communityCards[0] = PokerHandEvaluator.Card(0, 7);
        table.communityCards[1] = PokerHandEvaluator.Card(1, 8);
        table.communityCards[2] = PokerHandEvaluator.Card(2, 9);

        emit FlopDealt(tableId);
        return true;
    }

    function dealTurn(uint256 tableId) external override returns (bool) {
        if (msg.sender != address(gameState)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();
        if (table.gameState != GameState.Flop) revert InvalidGameState();

        // Add turn card
        table.communityCards.push(PokerHandEvaluator.Card(3, 10));

        emit TurnDealt(tableId);
        return true;
    }

    function dealRiver(uint256 tableId) external override returns (bool) {
        if (msg.sender != address(gameState)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();
        if (table.gameState != GameState.Turn) revert InvalidGameState();

        // Add river card
        table.communityCards.push(PokerHandEvaluator.Card(0, 11));

        emit RiverDealt(tableId);
        return true;
    }

    // Player action functions
    function fold(uint256 tableId, address player) external override returns (bool) {
        if (msg.sender != address(bettingContract)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        Player storage playerData = table.players[player];
        
        if (!table.isActive) revert TableNotFound();
        if (!playerData.isActive || !playerData.inHand) revert PlayerNotFound();
        if (table.currentPlayer != player) revert NotAuthorized();

        playerData.inHand = false;
        advanceToNextPlayer(tableId);
        return true;
    }

    function check(uint256 tableId, address player) external override returns (bool) {
        if (msg.sender != address(bettingContract)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        Player storage playerData = table.players[player];
        
        if (!table.isActive) revert TableNotFound();
        if (!playerData.isActive || !playerData.inHand) revert PlayerNotFound();
        if (table.currentPlayer != player) revert NotAuthorized();

        advanceToNextPlayer(tableId);
        return true;
    }

    function call(uint256 tableId, address player) external override returns (bool) {
        if (msg.sender != address(bettingContract)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        Player storage playerData = table.players[player];
        
        if (!table.isActive) revert TableNotFound();
        if (!playerData.isActive || !playerData.inHand) revert PlayerNotFound();
        if (table.currentPlayer != player) revert NotAuthorized();

        advanceToNextPlayer(tableId);
        return true;
    }

    function raise(uint256 tableId, address /* player */, uint256 /* amount */) external override returns (bool) {
        if (msg.sender != address(bettingContract)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        Player storage playerData = table.players[msg.sender];
        
        if (!table.isActive) revert TableNotFound();
        if (!playerData.isActive || !playerData.inHand) revert PlayerNotFound();
        if (table.currentPlayer != msg.sender) revert NotAuthorized();

        advanceToNextPlayer(tableId);
        return true;
    }

    // Internal functions
    function advanceToNextPlayer(uint256 tableId) public override returns (bool) {
        if (msg.sender != address(bettingContract) && msg.sender != address(this)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();

        // Find current player index
        uint256 currentIndex;
        for (uint256 i = 0; i < table.playerAddresses.length; i++) {
            if (table.playerAddresses[i] == table.currentPlayer) {
                currentIndex = i;
                break;
            }
        }

        // Find next active player
        uint256 nextIndex = (currentIndex + 1) % table.playerAddresses.length;
        while (nextIndex != currentIndex) {
            Player storage nextPlayer = table.players[table.playerAddresses[nextIndex]];
            if (nextPlayer.isActive && nextPlayer.inHand && !nextPlayer.isSittingOut) {
                table.currentPlayer = table.playerAddresses[nextIndex];
                return true;
            }
            nextIndex = (nextIndex + 1) % table.playerAddresses.length;
        }

        // If we get here, no other active players were found
        return false;
    }

    // Stake and pot management
    function updatePlayerBet(
        uint256 tableId,
        address player,
        uint256 betAmount,
        uint256 newStake
    ) external override returns (bool) {
        if (msg.sender != address(bettingContract)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        Player storage playerData = table.players[player];
        
        if (!table.isActive) revert TableNotFound();
        if (!playerData.isActive) revert PlayerNotFound();

        playerData.currentBet = betAmount;
        playerData.tableStake = newStake;
        return true;
    }

    function updatePlayerStake(
        uint256 tableId,
        address player,
        uint256 newStake
    ) external override returns (bool) {
        if (msg.sender != address(playerManager)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        Player storage playerData = table.players[player];
        
        if (!table.isActive) revert TableNotFound();
        if (!playerData.isActive) revert PlayerNotFound();

        playerData.tableStake = newStake;
        return true;
    }

    function updatePot(uint256 tableId, uint256 amount) external override returns (bool) {
        if (msg.sender != address(bettingContract)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        if (!table.isActive) revert TableNotFound();

        table.pot = amount;
        return true;
    }

    function awardPotToPlayer(
        uint256 tableId,
        address winner,
        uint256 amount
    ) external override returns (bool) {
        if (msg.sender != address(bettingContract) && msg.sender != address(gameState)) revert NotAuthorized();
        
        Table storage table = tables[tableId];
        Player storage playerData = table.players[winner];
        
        if (!table.isActive) revert TableNotFound();
        if (!playerData.isActive) revert PlayerNotFound();

        playerData.tableStake += amount;
        table.pot = 0;

        emit PotAwarded(tableId, winner, amount);
        return true;
    }
} 