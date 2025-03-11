// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./HouseTreasury.sol";
import "./IPokerTables.sol";

contract PokerTables is IPokerTables, Ownable, ReentrancyGuard {
    uint256 public minBetAmount;
    HouseTreasury public treasury;
    uint256 public maxTables = 10;
    uint256 public maxPlayersPerTable = 6; // 5 players + house
    
    // Table structure and related mappings
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
        mapping(address => Player) players;
        address[] playerAddresses;
        uint8[] communityCards;
        mapping(address => uint8[]) playerCards;
        mapping(uint256 => bool) hasActed;
        bool roundComplete;
    }

    // Mappings for game state
    mapping(uint256 => Table) public tables;
    mapping(address => uint256) public playerTables; // Which table a player is at
    uint256 public activeTableCount;

    // Events
    event TableCreated(uint256 indexed tableId, uint256 minBuyIn, uint256 maxBuyIn);
    event PlayerJoined(uint256 indexed tableId, address indexed player, uint256 buyIn);
    event PlayerLeft(uint256 indexed tableId, address indexed player, uint256 remainingStake);
    event GameStarted(uint256 indexed tableId);
    event TableConfigUpdated(
        uint256 indexed tableId,
        uint256 minBet,
        uint256 maxBet
    );
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);

    // Error messages
    error TableFull();
    error InvalidBuyIn();
    error PlayerNotAtTable();
    error TableNotActive();
    error InvalidBetLimits();
    error OnlyOwnerAllowed();

    constructor(uint256 _minBetAmount, address payable _treasuryAddress) Ownable(msg.sender) {
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
        
        // Log deployment info
        console.log("PokerTables deployed. Treasury address:", _treasuryAddress);
    }

    modifier onlyValidTable(uint256 tableId) {
        require(tables[tableId].isActive, "Table does not exist");
        _;
    }

    modifier onlyTablePlayer(uint256 tableId) {
        require(tables[tableId].players[msg.sender].isActive, "Not a player at this table");
        _;
    }

    /**
     * @dev Update the treasury address (in case it needs to be changed)
     */
    function setTreasuryAddress(address payable _treasuryAddress) external onlyOwner {
        address oldTreasury = address(treasury);
        treasury = HouseTreasury(_treasuryAddress);
        emit TreasuryAddressUpdated(oldTreasury, _treasuryAddress);
    }
    
    /**
     * @dev Check if contract is authorized in the treasury
     */
    function isAuthorizedInTreasury() public view returns (bool) {
        return treasury.authorizedGames(address(this));
    }

    /**
     * @dev Get player balance from treasury
     */
    function getPlayerTreasuryBalance(address player) public view returns (uint256) {
        return treasury.getPlayerBalance(player);
    }

    // Create a new table
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet
    ) external onlyOwner returns (uint256) {
        // Validate inputs
        if (minBuyIn >= maxBuyIn) revert InvalidBuyIn();
        if (minBet >= maxBet) revert InvalidBetLimits();
        if (smallBlind >= bigBlind) revert InvalidBetLimits();
        if (minBet < bigBlind) revert InvalidBetLimits();
        if (maxBet > maxBuyIn) revert InvalidBetLimits();

        uint256 tableId = activeTableCount++;
        Table storage newTable = tables[tableId];
        
        newTable.tableId = tableId;
        newTable.minBuyIn = minBuyIn;
        newTable.maxBuyIn = maxBuyIn;
        newTable.smallBlind = smallBlind;
        newTable.bigBlind = bigBlind;
        newTable.minBet = minBet;
        newTable.maxBet = maxBet;
        newTable.gameState = GameState.Waiting;
        newTable.isActive = true;

        emit TableCreated(tableId, minBuyIn, maxBuyIn);
        return tableId;
    }

    // Join a table - allows for either msg.sender or specified player (for testing)
    function joinTable(uint256 tableId, uint256 buyInAmount) 
        external 
        nonReentrant 
        onlyValidTable(tableId) 
    {
        // In this version, use msg.sender as the player
        address player = msg.sender;
        _joinTable(tableId, buyInAmount, player);
    }
    
    // Join table on behalf of another player (for testing)
    function joinTableForPlayer(uint256 tableId, uint256 buyInAmount, address player) 
        external 
        nonReentrant 
        onlyValidTable(tableId)
        onlyOwner
    {
        // Allow owner to join a player to table for testing purposes
        _joinTable(tableId, buyInAmount, player);
    }
    
    // Internal function to handle table joining logic
    function _joinTable(uint256 tableId, uint256 buyInAmount, address player) internal {
        Table storage table = tables[tableId];
        
        if (table.playerCount >= maxPlayersPerTable) revert TableFull();
        if (buyInAmount < table.minBuyIn || buyInAmount > table.maxBuyIn) revert InvalidBuyIn();
        
        // Debug logs
        console.log("Player trying to join table:", player);
        console.log("Contract authorized in treasury:", isAuthorizedInTreasury());
        console.log("Player treasury balance:", getPlayerTreasuryBalance(player));
        console.log("Buy-in amount:", buyInAmount);
        
        // Check if player has sufficient balance in treasury
        require(
            treasury.getPlayerBalance(player) >= buyInAmount,
            "Insufficient balance in treasury"
        );

        // Transfer buy-in from player's treasury balance to table stake
        treasury.processBetLoss(player, buyInAmount);
        
        // Add player to table
        table.players[player] = Player({
            playerAddress: player,
            tableStake: buyInAmount,
            currentBet: 0,
            isActive: true,
            isSittingOut: false,
            position: uint256(table.playerCount)
        });
        
        table.playerAddresses.push(player);
        table.playerCount++;
        playerTables[player] = tableId;
        
        emit PlayerJoined(tableId, player, buyInAmount);
        
        // Emit event to signal game can start if we have enough players
        if (table.playerCount >= 2 && table.gameState == GameState.Waiting) {
            emit GameStarted(tableId);
        }
    }

    // Leave table
    function leaveTable(uint256 tableId) 
        external 
        nonReentrant 
        onlyValidTable(tableId) 
    {
        // For regular gameplay, use msg.sender as player
        address player = msg.sender;
        _leaveTable(tableId, player);
    }
    
    // Leave table for a specific player (for testing)
    function leaveTableForPlayer(uint256 tableId, address player)
        external
        nonReentrant
        onlyValidTable(tableId)
        onlyOwner
    {
        // Allow owner to remove a player from table for testing
        _leaveTable(tableId, player);
    }
    
    // Internal function to handle leaving table logic
    function _leaveTable(uint256 tableId, address player) internal {
        Table storage table = tables[tableId];
        
        // Check if player is actually at the table
        require(playerTables[player] == tableId, "Player not at this table");
        
        Player storage playerInfo = table.players[player];
        require(playerInfo.playerAddress == player, "Player not found");
        
        // Allow leaving if player has either stake or active bet
        require(playerInfo.tableStake > 0 || playerInfo.currentBet > 0, "No stake or bet to withdraw");
        
        // Only return tableStake to treasury, currentBet stays in pot if in active hand
        if (playerInfo.tableStake > 0) {
            try treasury.processBetWin(player, playerInfo.tableStake) {
                // Success
            } catch {
                revert("Treasury transfer failed");
            }
        }
        
        uint256 remainingStake = playerInfo.tableStake;
        playerInfo.tableStake = 0;
        playerInfo.isActive = false;
        
        // Safely decrease player count
        if (table.playerCount > 0) {
            table.playerCount--;
        }
        
        // Remove from playerAddresses safely
        bool found = false;
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            if (table.playerAddresses[i] == player) {
                // Move last element to this position if it's not the last element
                if (i < table.playerAddresses.length - 1) {
                    table.playerAddresses[i] = table.playerAddresses[table.playerAddresses.length - 1];
                }
                table.playerAddresses.pop();
                found = true;
                break;
            }
        }
        require(found, "Player not found in addresses array");
        
        delete playerTables[player];
        
        emit PlayerLeft(tableId, player, remainingStake);
    }

    // Update table bet limits
    function updateTableBetLimits(
        uint256 tableId,
        uint256 newMinBet,
        uint256 newMaxBet
    ) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.isActive, "Table not active");
        require(table.gameState == GameState.Waiting, "Game in progress");
        
        if (newMinBet >= newMaxBet) revert InvalidBetLimits();
        if (newMinBet < table.bigBlind) revert InvalidBetLimits();
        if (newMaxBet > table.maxBuyIn) revert InvalidBetLimits();

        table.minBet = newMinBet;
        table.maxBet = newMaxBet;

        emit TableConfigUpdated(tableId, newMinBet, newMaxBet);
    }

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
    ) {
        Table storage table = tables[tableId];
        return (
            table.minBuyIn,
            table.maxBuyIn,
            table.smallBlind,
            table.bigBlind,
            table.minBet,
            table.maxBet,
            table.pot,
            table.playerCount,
            table.gameState,
            table.isActive
        );
    }

    function getPlayerInfo(uint256 tableId, address player) external view returns (
        uint256 tableStake,
        uint256 currentBet,
        bool isActive,
        bool isSittingOut,
        uint256 position
    ) {
        Player storage p = tables[tableId].players[player];
        return (
            p.tableStake,
            p.currentBet,
            p.isActive,
            p.isSittingOut,
            p.position
        );
    }

    // Get all players at a table
    function getTablePlayers(uint256 tableId) external view returns (address[] memory) {
        Table storage table = tables[tableId];
        return table.playerAddresses;
    }

    // Internal helper functions that might need to be exposed to the main contract
    function _getPlayerTableStake(uint256 tableId, address player) internal view returns (uint256) {
        return tables[tableId].players[player].tableStake;
    }

    function _updatePlayerTableStake(uint256 tableId, address player, uint256 newStake) internal {
        tables[tableId].players[player].tableStake = newStake;
    }

    function _updatePlayerBet(uint256 tableId, address player, uint256 betAmount) internal {
        tables[tableId].players[player].currentBet = betAmount;
    }

    function _addToPot(uint256 tableId, uint256 amount) internal {
        tables[tableId].pot += amount;
    }

    function _setGameState(uint256 tableId, GameState state) internal {
        tables[tableId].gameState = state;
    }
} 