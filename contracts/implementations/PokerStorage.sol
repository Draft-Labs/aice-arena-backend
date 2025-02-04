// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPokerBase.sol";

/**
 * @title PokerStorage
 * @dev Optimized storage contract for the poker game
 * Storage optimizations:
 * 1. Packed structs to use minimum slots
 * 2. Separated frequently and rarely accessed data
 * 3. Optimized mapping structures
 */
contract PokerStorage is Ownable {
    // Import GameState enum from IPokerBase
    enum GameState {
        Waiting,
        PreFlop,
        Flop,
        Turn,
        River,
        Showdown,
        Complete
    }
    
    // Packed Player struct (2 slots)
    struct PackedPlayer {
        // Slot 1
        address playerAddress;  // 20 bytes
        uint40 tableStake;     // 5 bytes (supports up to 1099511627775 wei)
        uint40 currentBet;     // 5 bytes
        uint8 position;        // 1 byte
        bool isActive;         // 1 byte
        bool isSittingOut;     // 1 byte
        
        // Slot 2 (for game state)
        uint8[] holeCards;     // Dynamic array (separate slot)
    }

    // Packed Table Configuration (3 slots)
    struct TableConfig {
        // Slot 1 (rarely updated values)
        uint40 minBuyIn;      // 5 bytes
        uint40 maxBuyIn;      // 5 bytes
        uint40 smallBlind;    // 5 bytes
        uint40 bigBlind;      // 5 bytes
        uint40 minBet;        // 5 bytes
        uint40 maxBet;        // 5 bytes
        bool isActive;        // 1 byte
        
        // Slot 2 (frequently updated values)
        uint40 pot;           // 5 bytes
        uint40 currentBet;    // 5 bytes
        uint8 dealerPosition; // 1 byte
        uint8 currentPosition;// 1 byte
        uint8 playerCount;    // 1 byte
        GameState gameState;  // 1 byte (enum)
        
        // Slot 3
        uint8[] communityCards; // Dynamic array (separate slot)
    }

    // Main storage
    mapping(uint256 => TableConfig) private tableConfigs;
    mapping(uint256 => mapping(address => PackedPlayer)) private tablePlayers;
    mapping(uint256 => address[]) private tablePlayerAddresses;
    mapping(address => uint256) private playerTableIds;
    mapping(uint256 => mapping(uint256 => bool)) private hasActed;
    uint256 public activeTableCount;

    // Events
    event TableConfigUpdated(uint256 indexed tableId);
    event PlayerDataUpdated(uint256 indexed tableId, address indexed player);

    constructor() Ownable(msg.sender) {}

    // Setters with access control
    function setTableConfig(uint256 tableId, TableConfig memory config) external onlyOwner {
        tableConfigs[tableId] = config;
        emit TableConfigUpdated(tableId);
    }

    function setPlayer(uint256 tableId, address playerAddress, PackedPlayer memory player) external onlyOwner {
        tablePlayers[tableId][playerAddress] = player;
        emit PlayerDataUpdated(tableId, playerAddress);
    }

    function addPlayerToTable(uint256 tableId, address player) external onlyOwner {
        tablePlayerAddresses[tableId].push(player);
        playerTableIds[player] = tableId;
    }

    function removePlayerFromTable(uint256 tableId, address player) external onlyOwner {
        address[] storage players = tablePlayerAddresses[tableId];
        for (uint i = 0; i < players.length; i++) {
            if (players[i] == player) {
                players[i] = players[players.length - 1];
                players.pop();
                break;
            }
        }
        delete playerTableIds[player];
    }

    function setPlayerHasActed(uint256 tableId, uint256 position, bool acted) external onlyOwner {
        hasActed[tableId][position] = acted;
    }

    function incrementActiveTableCount() external onlyOwner {
        activeTableCount++;
    }

    function decrementActiveTableCount() external onlyOwner {
        if (activeTableCount > 0) {
            activeTableCount--;
        }
    }

    // Getters
    function getTableConfig(uint256 tableId) external view returns (TableConfig memory) {
        return tableConfigs[tableId];
    }

    function getPlayer(uint256 tableId, address playerAddress) external view returns (PackedPlayer memory) {
        return tablePlayers[tableId][playerAddress];
    }

    function getTablePlayers(uint256 tableId) external view returns (address[] memory) {
        return tablePlayerAddresses[tableId];
    }

    function getPlayerTableId(address player) external view returns (uint256) {
        return playerTableIds[player];
    }

    function getPlayerHasActed(uint256 tableId, uint256 position) external view returns (bool) {
        return hasActed[tableId][position];
    }

    // Batch operations for gas optimization
    function updateMultiplePlayerStakes(
        uint256 tableId,
        address[] calldata players,
        uint40[] calldata newStakes
    ) external onlyOwner {
        require(players.length == newStakes.length, "Array length mismatch");
        for (uint i = 0; i < players.length; i++) {
            PackedPlayer storage player = tablePlayers[tableId][players[i]];
            player.tableStake = newStakes[i];
            emit PlayerDataUpdated(tableId, players[i]);
        }
    }

    function resetRoundState(uint256 tableId) external onlyOwner {
        TableConfig storage config = tableConfigs[tableId];
        config.currentBet = 0;
        address[] memory players = tablePlayerAddresses[tableId];
        for (uint i = 0; i < players.length; i++) {
            PackedPlayer storage player = tablePlayers[tableId][players[i]];
            player.currentBet = 0;
            hasActed[tableId][i] = false;
        }
        emit TableConfigUpdated(tableId);
    }
} 