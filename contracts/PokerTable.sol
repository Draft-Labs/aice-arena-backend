// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./HouseTreasury.sol";
import "./PokerEvents.sol";

contract PokerTable is Ownable, ReentrancyGuard, PokerEvents {
    uint256 public minBetAmount;
    HouseTreasury public treasury;
    uint256 public maxTables = 10;
    uint256 public maxPlayersPerTable = 6; // 5 players + house

    struct Player {
        address playerAddress;
        uint256 tableStake;     // Current chips at table
        uint256 currentBet;     // Current bet in the round
        bool isActive;          // Still in the current hand
        bool isSittingOut;      // Temporarily sitting out
        uint256 position;       // Position at table (0-5)
    }

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

    constructor(uint256 _minBetAmount, address payable _treasuryAddress) Ownable(msg.sender) {
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
    }

    modifier onlyValidTable(uint256 tableId) {
        require(tables[tableId].isActive, "Table does not exist");
        _;
    }

    modifier onlyTablePlayer(uint256 tableId) {
        require(tables[tableId].players[msg.sender].isActive, "Not a player at this table");
        _;
    }

    modifier onlyDuringState(uint256 tableId, GameState state) {
        require(tables[tableId].gameState == state, "Invalid game state");
        _;
    }

    // Create a new table
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet
    ) public virtual returns (uint256) {
        if (owner() != msg.sender) revert OnlyOwnerAllowed();
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

    // Join a table
    function joinTable(uint256 tableId, uint256 buyInAmount) 
        virtual public 
        nonReentrant 
        onlyValidTable(tableId) 
    {
        Table storage table = tables[tableId];
        
        if (table.playerCount >= maxPlayersPerTable) revert TableFull();
        if (buyInAmount < table.minBuyIn || buyInAmount > table.maxBuyIn) revert InvalidBuyIn();
        
        // Check if player has sufficient balance in treasury
        require(
            treasury.getPlayerBalance(msg.sender) >= buyInAmount,
            "Insufficient balance in treasury"
        );

        // Transfer buy-in from player's treasury balance to table stake
        treasury.processBetLoss(msg.sender, buyInAmount);
        
        // Add player to table
        table.players[msg.sender] = Player({
            playerAddress: msg.sender,
            tableStake: buyInAmount,
            currentBet: 0,
            isActive: true,
            isSittingOut: false,
            position: uint256(table.playerCount)
        });
        
        table.playerAddresses.push(msg.sender);
        table.playerCount++;
        playerTables[msg.sender] = tableId;
        
        emit PlayerJoined(tableId, msg.sender, buyInAmount);
    }

    // Leave table
    function leaveTable(uint256 tableId) 
        virtual public 
        nonReentrant 
        onlyValidTable(tableId) 
    {
        Table storage table = tables[tableId];
        
        // Check if player is actually at the table
        require(playerTables[msg.sender] == tableId, "Player not at this table");
        
        Player storage player = table.players[msg.sender];
        require(player.playerAddress == msg.sender, "Player not found");
        
        // Allow leaving if player has either stake or active bet
        require(player.tableStake > 0 || player.currentBet > 0, "No stake or bet to withdraw");
        
        // Only return tableStake to treasury, currentBet stays in pot if in active hand
        if (player.tableStake > 0) {
            try treasury.processBetWin(msg.sender, player.tableStake) {
                // Success
            } catch {
                revert("Treasury transfer failed");
            }
        }
        
        uint256 remainingStake = player.tableStake;
        player.tableStake = 0;
        player.isActive = false;
        
        // Safely decrease player count
        if (table.playerCount > 0) {
            table.playerCount--;
        }
        
        // Remove from playerAddresses safely
        bool found = false;
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            if (table.playerAddresses[i] == msg.sender) {
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
        
        delete playerTables[msg.sender];
        
        emit PlayerLeft(tableId, msg.sender, remainingStake);
    }

    // View functions
    function getTableInfo(uint256 tableId) virtual public view returns (
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet,
        uint256 pot,
        uint256 playerCount,
        uint8 gameState,
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
            uint8(table.gameState),
            table.isActive
        );
    }

    function getPlayerInfo(uint256 tableId, address player) virtual public view returns (
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

    // Add function to update bet limits
    function updateTableBetLimits(
        uint256 tableId,
        uint256 newMinBet,
        uint256 newMaxBet
    ) external {
        if (owner() != msg.sender) revert OnlyOwnerAllowed();
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

    // Internal function for derived contracts
    function _getTablePlayers(uint256 tableId) internal view returns (address[] memory) {
        Table storage table = tables[tableId];
        return table.playerAddresses;
    }

    // External interface for external callers
    function getTablePlayers(uint256 tableId) virtual public view returns (address[] memory) {
        return _getTablePlayers(tableId);
    }

    // Internal helper functions
    function moveToNextPlayer(uint256 tableId) virtual internal {
        Table storage table = tables[tableId];
        require(table.playerCount > 0, "No players at table");
        require(table.playerAddresses.length > 0, "No player addresses");
        require(table.currentPosition < table.playerAddresses.length, "Invalid current position");
        
        bool foundNext = false;
        uint256 startingPosition = table.currentPosition;
        
        // Try to find next active player
        for (uint256 i = 1; i <= table.playerAddresses.length; i++) {
            uint256 nextPosition = (startingPosition + i) % table.playerAddresses.length;
            address nextPlayer = table.playerAddresses[nextPosition];
            
            if (nextPlayer != address(0) && table.players[nextPlayer].isActive) {
                table.currentPosition = nextPosition;
                foundNext = true;
                emit TurnStarted(tableId, nextPlayer);
                break;
            }
        }
    }

    // Helper function to reset bets between rounds
    function resetBets(uint256 tableId) internal {
        Table storage table = tables[tableId];
        
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            if (table.players[playerAddr].isActive) {
                table.players[playerAddr].currentBet = 0;
            }
        }
    }

    function dealPlayerCards(uint256 tableId, address player, uint8[] memory cards) 
        virtual internal 
        onlyValidTable(tableId) 
    {
        require(cards.length == 2, "Must deal exactly 2 cards");
        Table storage table = tables[tableId];
        require(table.players[player].isActive, "Player not active");
        
        delete table.playerCards[player];
        for (uint i = 0; i < cards.length; i++) {
            table.playerCards[player].push(cards[i]);
        }
        
        emit CardsDealt(tableId, player, cards);
    }

    function dealCommunityCards(uint256 tableId, uint8[] memory cards) 
        virtual internal 
        onlyValidTable(tableId) 
    {
        Table storage table = tables[tableId];
        
        // Store the cards
        for (uint i = 0; i < cards.length; i++) {
            table.communityCards.push(cards[i]);
        }
        
        emit CommunityCardsDealt(tableId, cards);
    }

    function getPlayerCards(uint256 tableId, address player) 
        public 
        view 
        returns (uint8[] memory) 
    {
        Table storage table = tables[tableId];
        require(player == msg.sender || msg.sender == owner(), "Not authorized");
        return table.playerCards[player];
    }

    // Game state management functions
    function setGameState(uint256 tableId, GameState state) virtual internal {
        tables[tableId].gameState = state;
        emit GameStateChanged(tableId, uint8(state));
    }

    function getGameState(uint256 tableId) virtual public view returns (uint8) {
        return uint8(tables[tableId].gameState);
    }

    function resetTableForNewHand(uint256 tableId) virtual internal {
        Table storage table = tables[tableId];
        delete table.communityCards;
        resetBets(tableId);
        table.pot = 0;
        table.currentBet = 0;
        table.roundComplete = false;
        
        // Reset player states
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            if (table.players[playerAddr].tableStake > 0) {
                table.players[playerAddr].isActive = true;
                table.players[playerAddr].currentBet = 0;
                delete table.playerCards[playerAddr];
            }
        }
    }

    function isPlayerTurn(uint256 tableId, address player) virtual public view returns (bool) {
        Table storage table = tables[tableId];
        return table.playerAddresses[table.currentPosition] == player;
    }

    function isPlayerActive(uint256 tableId, address player) virtual public view returns (bool) {
        return tables[tableId].players[player].isActive;
    }

    function setPlayerActive(uint256 tableId, address player, bool active) virtual internal {
        tables[tableId].players[player].isActive = active;
    }

    function setPlayerHasActed(uint256 tableId, address player, bool hasActed) virtual internal {
        tables[tableId].hasActed[tables[tableId].players[player].position] = hasActed;
    }

    function getPlayerCurrentBet(uint256 tableId, address player) virtual public view returns (uint256) {
        return tables[tableId].players[player].currentBet;
    }

    function getTableCurrentBet(uint256 tableId) virtual public view returns (uint256) {
        return tables[tableId].currentBet;
    }

    function getPlayerTableStake(uint256 tableId, address player) virtual public view returns (uint256) {
        return tables[tableId].players[player].tableStake;
    }

    function updatePlayerBet(uint256 tableId, address player, uint256 betAmount) virtual internal {
        Table storage table = tables[tableId];
        Player storage p = table.players[player];
        
        require(p.tableStake >= betAmount, "Insufficient table stake");
        
        p.tableStake -= betAmount;
        p.currentBet += betAmount;
        table.pot += betAmount;
        
        if (betAmount > table.currentBet) {
            table.currentBet = betAmount;
        }
    }

    function getTableBigBlind(uint256 tableId) virtual public view returns (uint256) {
        return tables[tableId].bigBlind;
    }

    function getTableSmallBlind(uint256 tableId) virtual public view returns (uint256) {
        return tables[tableId].smallBlind;
    }

    function getTablePot(uint256 tableId) virtual public view returns (uint256) {
        return tables[tableId].pot;
    }

    function awardPotToPlayer(uint256 tableId, address winner) virtual internal {
        Table storage table = tables[tableId];
        Player storage player = table.players[winner];
        
        uint256 potAmount = table.pot;
        player.tableStake += potAmount;
        table.pot = 0;
    }

    function getPlayerCount(uint256 tableId) virtual public view returns (uint256) {
        return tables[tableId].playerCount;
    }

    function getCurrentPlayer(uint256 tableId) virtual public view returns (address) {
        Table storage table = tables[tableId];
        if (table.currentPosition >= table.playerAddresses.length) {
            return address(0);
        }
        return table.playerAddresses[table.currentPosition];
    }

    function hasNextActivePlayer(uint256 tableId) virtual public view returns (bool) {
        Table storage table = tables[tableId];
        uint256 startingPosition = table.currentPosition;
        
        
        for (uint256 i = 1; i <= table.playerAddresses.length; i++) {
            uint256 nextPosition = (startingPosition + i) % table.playerAddresses.length;
            address nextPlayer = table.playerAddresses[nextPosition];
            
            if (nextPlayer != address(0) && table.players[nextPlayer].isActive) {
                return true;
            }
        }
        return false;
    }

    function isRoundComplete(uint256 tableId) virtual public view returns (bool) {
        Table storage table = tables[tableId];
        
        // Check if all active players have acted
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            if (table.players[playerAddr].isActive && !table.hasActed[i]) {
                return false;
            }
        }
        return true;
    }

    function resetRound(uint256 tableId) virtual internal {
        Table storage table = tables[tableId];
        
        // Reset all player actions for the new round
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            table.hasActed[i] = false;
        }
        
        // Reset bets for the new round
        resetBets(tableId);
        table.currentBet = 0;
    }

    function getCommunityCards(uint256 tableId) virtual public view returns (uint8[] memory) {
        return tables[tableId].communityCards;
    }
}
