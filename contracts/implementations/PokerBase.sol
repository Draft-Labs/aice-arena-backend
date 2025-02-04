// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IPokerBase.sol";
import "./PokerStorage.sol";

contract PokerBase is IPokerBase, Ownable, ReentrancyGuard {
    // Constants
    uint256 public constant MAX_TABLES = 10;
    uint256 public constant MAX_PLAYERS_PER_TABLE = 6;
    uint256 public constant MIN_PLAYERS_TO_START = 2;

    // Storage contract
    PokerStorage public immutable storage_;

    constructor(address storageAddress) Ownable(msg.sender) {
        storage_ = PokerStorage(storageAddress);
    }

    // Modifiers
    modifier onlyValidTable(uint256 tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        if (!config.isActive) revert TableNotActive();
        _;
    }

    modifier onlyTablePlayer(uint256 tableId) {
        if (!isPlayerAtTable(tableId, msg.sender)) revert PlayerNotAtTable();
        _;
    }

    modifier onlyDuringState(uint256 tableId, GameState state) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        if (config.gameState != state) revert InvalidGameState();
        _;
    }

    // Public view functions
    function isPlayerAtTable(uint256 tableId, address player) public view returns (bool) {
        PokerStorage.PackedPlayer memory p = storage_.getPlayer(tableId, player);
        return p.playerAddress == player;
    }

    function getTable(uint256 tableId) public view returns (Table memory) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
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
        return storage_.getTablePlayers(tableId);
    }

    function getPlayerCardArray(uint256 tableId, address player) public view returns (uint8[] memory) {
        PokerStorage.PackedPlayer memory p = storage_.getPlayer(tableId, player);
        return p.holeCards;
    }

    function getCommunityCardArray(uint256 tableId) public view returns (uint8[] memory) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        return config.communityCards;
    }

    function getPlayerTableId(address player) public view returns (uint256) {
        return storage_.getPlayerTableId(player);
    }

    function hasPlayerActed(uint256 tableId, uint256 position) public view returns (bool) {
        return storage_.getPlayerHasActed(tableId, position);
    }

    // Internal storage setters
    function _setTable(uint256 tableId, Table memory table) internal {
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
} 