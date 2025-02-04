// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IPokerBase.sol";
import "./PokerStorage.sol";
import "./PokerAccessControl.sol";
import "./PokerInputValidation.sol";
import "./PokerGameSecurity.sol";

contract PokerBase is IPokerBase, Ownable, ReentrancyGuard, PokerAccessControl, PokerInputValidation, PokerGameSecurity {
    // Constants
    uint256 public constant MAX_TABLES = 10;
    uint256 public constant MAX_PLAYERS_PER_TABLE = 6;
    uint256 public constant MIN_PLAYERS_TO_START = 2;

    // Storage contract
    PokerStorage public immutable storage_;

    constructor(address storageAddress) validateAddress(storageAddress) {
        storage_ = PokerStorage(storageAddress);
    }

    // Enhanced modifiers with game security
    modifier onlyValidTable(uint256 tableId) {
        require(!paused(), "Game is paused");
        require(tableId < maxTableLimit, "Invalid table ID");
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(config.isActive, "Table not active");
        require(gameTimers[tableId].isActive, "Game timer not active");
        _;
    }

    modifier onlyTablePlayer(uint256 tableId) {
        require(!paused(), "Game is paused");
        require(msg.sender != address(0), "Invalid player address");
        require(isPlayerAtTable(tableId, msg.sender), "Not at table");
        require(!checkTimeout(tableId, msg.sender), "Player timed out");
        _;
    }

    modifier onlyDuringState(uint256 tableId, GameState state) {
        require(!paused(), "Game is paused");
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(uint8(state) <= MAX_ROUNDS, "Invalid game state");
        require(config.gameState == state, "Invalid game state");
        require(isWithinTurnTime(tableId, msg.sender), "Turn time expired");
        _;
    }

    modifier validateTurnTimeout(uint256 tableId) {
        require(isWithinTurnTime(tableId, msg.sender), "Turn time expired");
        checkAndEmitTimeoutWarning(tableId, msg.sender);
        _;
    }

    modifier validateBetAmount(uint256 amount) {
        validateBetAmount(amount);
        _;
    }

    // Public view functions with enhanced validation
    function isPlayerAtTable(uint256 tableId, address player) public view returns (bool) {
        require(!paused(), "Game is paused");
        require(player != address(0), "Invalid player address");
        PokerStorage.PackedPlayer memory p = storage_.getPlayer(tableId, player);
        return p.playerAddress == player;
    }

    function getTable(uint256 tableId) public view returns (Table memory) {
        require(!paused(), "Game is paused");
        require(tableId < maxTableLimit, "Invalid table ID");
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        validateTableCount(tableId);
        return Table({
            tableId: tableId,
            minBuyIn: config.minBuyIn,
            maxBuyIn: config.maxBuyIn,
            smallBlind: config.smallBlind,
            bigBlind: config.bigBlind,
            minBet: config.minBet,
            maxBet: config.maxBet,
            pot: config.pot,
            currentBet: config.currentBet,
            dealerPosition: config.dealerPosition,
            currentPosition: config.currentPosition,
            playerCount: config.playerCount,
            gameState: config.gameState,
            isActive: config.isActive
        });
    }

    function getPlayer(uint256 tableId, address playerAddress) public view returns (Player memory) {
        require(!paused(), "Game is paused");
        require(playerAddress != address(0), "Invalid player address");
        PokerStorage.PackedPlayer memory p = storage_.getPlayer(tableId, playerAddress);
        return Player({
            playerAddress: p.playerAddress,
            tableStake: p.tableStake,
            currentBet: p.currentBet,
            isActive: p.isActive,
            isSittingOut: p.isSittingOut,
            position: p.position
        });
    }

    function getTablePlayerAddresses(uint256 tableId) public view returns (address[] memory) {
        require(tableId < maxTableLimit, "Invalid table ID");
        return storage_.getTablePlayers(tableId);
    }

    function getPlayerCardArray(uint256 tableId, address player) public view returns (uint8[] memory) {
        require(player != address(0), "Invalid player address");
        PokerStorage.PackedPlayer memory p = storage_.getPlayer(tableId, player);
        require(validatePlayerCards(p.holeCards), "Invalid player cards");
        return p.holeCards;
    }

    function getCommunityCardArray(uint256 tableId) public view returns (uint8[] memory) {
        require(tableId < maxTableLimit, "Invalid table ID");
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(validateCommunityCards(config.communityCards), "Invalid community cards");
        return config.communityCards;
    }

    function getPlayerTableId(address player) public view returns (uint256) {
        return storage_.getPlayerTableId(player);
    }

    function hasPlayerActed(uint256 tableId, uint256 position) public view returns (bool) {
        return storage_.getPlayerHasActed(tableId, position);
    }

    // Internal storage setters with enhanced validation
    function _setTable(uint256 tableId, Table memory table) internal {
        require(!paused(), "Game is paused");
        require(tableId < maxTableLimit, "Invalid table ID");
        validateTableCount(tableId);
        validatePlayerCount(table.playerCount);
        require(validateBlinds(table.smallBlind, table.bigBlind), "Invalid blinds");
        require(validateBuyIn(table.minBuyIn, MIN_BUY_IN, MAX_BUY_IN), "Invalid min buy-in");
        require(validateBuyIn(table.maxBuyIn, table.minBuyIn, MAX_BUY_IN), "Invalid max buy-in");
        
        PokerStorage.TableConfig memory config = PokerStorage.TableConfig({
            minBuyIn: uint40(table.minBuyIn),
            maxBuyIn: uint40(table.maxBuyIn),
            smallBlind: uint40(table.smallBlind),
            bigBlind: uint40(table.bigBlind),
            minBet: uint40(table.minBet),
            maxBet: uint40(table.maxBet),
            pot: uint40(table.pot),
            currentBet: uint40(table.currentBet),
            dealerPosition: uint8(table.dealerPosition),
            currentPosition: uint8(table.currentPosition),
            playerCount: uint8(table.playerCount),
            gameState: table.gameState,
            isActive: table.isActive,
            communityCards: new uint8[](0)
        });
        storage_.setTableConfig(tableId, config);
    }

    function _setPlayer(uint256 tableId, address playerAddress, Player memory player) internal {
        require(!paused(), "Game is paused");
        require(playerAddress != address(0), "Invalid player address");
        require(validateBet(player.tableStake, 0, maxBetLimit, type(uint256).max), "Invalid table stake");
        require(validateBet(player.currentBet, 0, maxBetLimit, player.tableStake), "Invalid current bet");
        require(validatePosition(uint8(player.position), MAX_PLAYERS), "Invalid position");
        
        PokerStorage.PackedPlayer memory p = PokerStorage.PackedPlayer({
            playerAddress: player.playerAddress,
            tableStake: uint40(player.tableStake),
            currentBet: uint40(player.currentBet),
            position: uint8(player.position),
            isActive: player.isActive,
            isSittingOut: player.isSittingOut,
            holeCards: new uint8[](0)
        });
        storage_.setPlayer(tableId, playerAddress, p);
    }

    function _addTablePlayer(uint256 tableId, address player) internal {
        storage_.addPlayerToTable(tableId, player);
    }

    function _removeTablePlayer(uint256 tableId, address player) internal {
        storage_.removePlayerFromTable(tableId, player);
    }

    function _setPlayerHasActed(uint256 tableId, uint256 position, bool acted) internal {
        storage_.setPlayerHasActed(tableId, position, acted);
    }

    function _setPlayerTableId(address player, uint256 tableId) internal {
        storage_.addPlayerToTable(tableId, player);
    }

    function _incrementActiveTableCount() internal {
        storage_.incrementActiveTableCount();
    }

    function _decrementActiveTableCount() internal {
        storage_.decrementActiveTableCount();
    }

    // Emergency functions
    function emergencyWithdraw(uint256 tableId, address player) external onlyEmergencyAdmin {
        require(paused(), "Game must be paused for emergency withdrawal");
        PokerStorage.PackedPlayer memory p = storage_.getPlayer(tableId, player);
        require(p.playerAddress == player, "Player not found");
        validateEmergencyWithdrawal(block.timestamp);
        
        uint256 amount = p.tableStake + p.currentBet;
        require(amount > 0, "No funds to withdraw");
        
        // Reset player state
        p.tableStake = 0;
        p.currentBet = 0;
        p.isActive = false;
        storage_.setPlayer(tableId, player, p);
        
        // Emit emergency withdrawal event
        emit EmergencyWithdrawal(tableId, player, amount);
    }

    // Events
    event EmergencyWithdrawal(uint256 indexed tableId, address indexed player, uint256 amount);

    // Game state transition functions with enhanced security
    function startNewHand(uint256 tableId) external onlyOwner onlyValidTable(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(
            config.gameState == GameState.Complete || config.gameState == GameState.Waiting,
            "Invalid game state"
        );
        
        // Validate game state transition
        require(
            validateGameState(
                tableId,
                uint8(config.gameState),
                uint8(GameState.PreFlop),
                config.playerCount,
                config.pot
            ),
            "Invalid state transition"
        );
        
        // Reset game state
        config.gameState = GameState.PreFlop;
        config.pot = 0;
        config.currentBet = 0;
        config.dealerPosition = uint8((config.dealerPosition + 1) % config.playerCount);
        config.currentPosition = uint8((config.dealerPosition + 1) % config.playerCount);
        
        // Reset all player states and timers
        address[] memory tablePlayers = storage_.getTablePlayers(tableId);
        for (uint i = 0; i < tablePlayers.length; i++) {
            PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, tablePlayers[i]);
            player.currentBet = 0;
            player.isActive = !player.isSittingOut && player.tableStake > 0;
            storage_.setPlayer(tableId, tablePlayers[i], player);
            storage_.setPlayerHasActed(tableId, i, false);
            updatePlayerTimer(tableId, tablePlayers[i]);
        }
        
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized round state event (PreFlop)
        emit RoundState(
            tableId,
            0, // 0 = PreFlop
            0,
            uint8(getActivePlayerCount(tableId))
        );
    }

    // Player action functions with timeout handling
    function moveToNextPlayer(uint256 tableId) internal {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        address[] memory tablePlayers = storage_.getTablePlayers(tableId);
        
        uint256 startingPosition = config.currentPosition;
        bool foundNext = false;
        
        // Try to find next active player
        for (uint256 i = 1; i <= tablePlayers.length; i++) {
            uint256 nextPosition = (startingPosition + i) % tablePlayers.length;
            address nextPlayer = tablePlayers[nextPosition];
            
            if (storage_.getPlayer(tableId, nextPlayer).isActive && !checkTimeout(tableId, nextPlayer)) {
                config.currentPosition = uint8(nextPosition);
                foundNext = true;
                storage_.setTableConfig(tableId, config);
                updatePlayerTimer(tableId, nextPlayer);
                emit TurnStarted(tableId, nextPlayer);
                break;
            }
        }
        
        if (!foundNext || isRoundComplete(tableId)) {
            emit RoundComplete(tableId);
        }
    }

    // Timeout handling
    function handleTimeout(uint256 tableId, address player) external onlyGameAdmin {
        require(checkTimeout(tableId, player), "No timeout occurred");
        
        PokerStorage.PackedPlayer memory p = storage_.getPlayer(tableId, player);
        p.isActive = false;
        storage_.setPlayer(tableId, player, p);
        
        enforceTimeout(tableId, player);
        moveToNextPlayer(tableId);
    }

    // Dispute handling
    function handleDispute(
        uint256 tableId,
        address defendant,
        string memory reason
    ) external payable {
        require(isPlayerAtTable(tableId, msg.sender), "Not at table");
        require(isPlayerAtTable(tableId, defendant), "Defendant not at table");
        
        createDispute(tableId, defendant, reason);
    }
} 