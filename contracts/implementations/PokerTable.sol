// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPokerTable.sol";
import "./PokerBase.sol";

contract PokerTable is IPokerTable, PokerBase {
    constructor(address storageAddress) PokerBase(storageAddress) {}

    // Table management
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet
    ) external onlyOwner returns (uint256 tableId) {
        require(storage_.activeTableCount() < MAX_TABLES, "Maximum tables reached");
        require(minBuyIn < maxBuyIn, "Invalid buy-in range");
        require(smallBlind < bigBlind, "Invalid blind values");
        require(minBet >= bigBlind, "Min bet must be >= big blind");
        require(maxBet <= maxBuyIn, "Max bet must be <= max buy-in");

        tableId = storage_.activeTableCount();
        
        PokerStorage.TableConfig memory config = PokerStorage.TableConfig({
            minBuyIn: uint40(minBuyIn),
            maxBuyIn: uint40(maxBuyIn),
            smallBlind: uint40(smallBlind),
            bigBlind: uint40(bigBlind),
            minBet: uint40(minBet),
            maxBet: uint40(maxBet),
            pot: 0,
            currentBet: 0,
            dealerPosition: 0,
            currentPosition: 0,
            playerCount: 0,
            gameState: PokerStorage.GameState.Waiting,
            isActive: true,
            communityCards: new uint8[](0)
        });

        storage_.setTableConfig(tableId, config);
        storage_.incrementActiveTableCount();

        // Emit optimized table event (Created)
        emit TableEvent(
            tableId,
            0, // 0 = Created
            uint40(minBuyIn),
            uint40(maxBuyIn),
            uint40(minBet),
            uint40(maxBet)
        );
        return tableId;
    }

    function joinTable(uint256 tableId, uint256 buyInAmount) external onlyValidTable(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(config.playerCount < MAX_PLAYERS_PER_TABLE, "Table is full");
        require(buyInAmount >= config.minBuyIn && buyInAmount <= config.maxBuyIn, "Invalid buy-in amount");
        require(!isPlayerAtTable(tableId, msg.sender), "Already at table");

        PokerStorage.PackedPlayer memory newPlayer = PokerStorage.PackedPlayer({
            playerAddress: msg.sender,
            tableStake: uint40(buyInAmount),
            currentBet: 0,
            position: uint8(config.playerCount),
            isActive: true,
            isSittingOut: false,
            holeCards: new uint8[](0)
        });

        storage_.setPlayer(tableId, msg.sender, newPlayer);
        storage_.addPlayerToTable(tableId, msg.sender);

        config.playerCount++;
        storage_.setTableConfig(tableId, config);

        // Emit optimized player event (Joined)
        emit PlayerEvent(
            tableId,
            msg.sender,
            0, // 0 = Joined
            uint40(buyInAmount)
        );
    }

    function leaveTable(uint256 tableId) external onlyValidTable(tableId) onlyTablePlayer(tableId) {
        PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, msg.sender);
        require(player.tableStake > 0 || player.currentBet > 0, "No stake to withdraw");

        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        
        // Return stake to player
        if (player.tableStake > 0) {
            uint256 remainingStake = player.tableStake;
            player.tableStake = 0;
            player.isActive = false;
            storage_.setPlayer(tableId, msg.sender, player);

            // Emit optimized player event (Left)
            emit PlayerEvent(
                tableId,
                msg.sender,
                1, // 1 = Left
                uint40(remainingStake)
            );
        }

        // Update table state
        config.playerCount--;
        storage_.setTableConfig(tableId, config);
        
        // Remove player from table data structures
        storage_.removePlayerFromTable(tableId, msg.sender);
    }

    function sitOut(uint256 tableId) external onlyValidTable(tableId) onlyTablePlayer(tableId) {
        PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, msg.sender);
        require(!player.isSittingOut, "Already sitting out");

        player.isSittingOut = true;
        storage_.setPlayer(tableId, msg.sender, player);

        // Emit optimized player event (SitOut)
        emit PlayerEvent(
            tableId,
            msg.sender,
            2, // 2 = SitOut
            uint40(player.tableStake)
        );
    }

    function sitIn(uint256 tableId) external onlyValidTable(tableId) onlyTablePlayer(tableId) {
        PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, msg.sender);
        require(player.isSittingOut, "Not sitting out");
        require(player.tableStake >= storage_.getTableConfig(tableId).minBuyIn, "Insufficient stake to sit in");

        player.isSittingOut = false;
        storage_.setPlayer(tableId, msg.sender, player);

        // Emit optimized player event (SitIn)
        emit PlayerEvent(
            tableId,
            msg.sender,
            3, // 3 = SitIn
            uint40(player.tableStake)
        );
    }

    // Table queries
    function getTableInfo(uint256 tableId) external view returns (Table memory) {
        return getTable(tableId);
    }

    function getPlayerInfo(uint256 tableId, address player) external view returns (Player memory) {
        return getPlayer(tableId, player);
    }

    function getTablePlayers(uint256 tableId) external view returns (address[] memory) {
        return storage_.getTablePlayers(tableId);
    }

    function getActiveTables() external view returns (uint256[] memory) {
        uint256[] memory activeTables = new uint256[](storage_.activeTableCount());
        uint256 index = 0;
        
        for (uint256 i = 0; i < storage_.activeTableCount(); i++) {
            if (storage_.getTableConfig(i).isActive) {
                activeTables[index] = i;
                index++;
            }
        }
        
        return activeTables;
    }

    function getMaxTables() external pure returns (uint256) {
        return MAX_TABLES;
    }

    function getMaxPlayersPerTable() external pure returns (uint256) {
        return MAX_PLAYERS_PER_TABLE;
    }

    function isTableActive(uint256 tableId) external view returns (bool) {
        return storage_.getTableConfig(tableId).isActive;
    }

    function getPlayerCount(uint256 tableId) external view returns (uint256) {
        return storage_.getTableConfig(tableId).playerCount;
    }

    function isPlayerAtTable(uint256 tableId, address player) public view override(IPokerTable, PokerBase) returns (bool) {
        return super.isPlayerAtTable(tableId, player);
    }

    // Table configuration
    function updateTableConfig(
        uint256 tableId,
        uint256 minBet,
        uint256 maxBet
    ) external onlyOwner onlyValidTable(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(config.gameState == PokerStorage.GameState.Waiting, "Game in progress");
        require(minBet >= config.bigBlind, "Min bet must be >= big blind");
        require(maxBet <= config.maxBuyIn, "Max bet must be <= max buy-in");
        require(minBet < maxBet, "Invalid bet range");

        config.minBet = uint40(minBet);
        config.maxBet = uint40(maxBet);
        storage_.setTableConfig(tableId, config);

        // Emit optimized table event (Updated)
        emit TableEvent(
            tableId,
            1, // 1 = Updated
            uint40(config.minBuyIn),
            uint40(config.maxBuyIn),
            uint40(minBet),
            uint40(maxBet)
        );
    }
} 