// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./HouseTreasury.sol";

contract Poker is ReentrancyGuard {
    address public owner;
    uint256 public minBetAmount;
    HouseTreasury public treasury;
    uint256 public maxTables = 10;
    uint256 public maxPlayersPerTable = 6; // 5 players + house
    
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

    struct Player {
        address playerAddress;
        uint256 tableStake;     // Current chips at table
        uint256 currentBet;     // Current bet in the round
        bool isActive;          // Still in the current hand
        bool isSittingOut;      // Temporarily sitting out
        uint8 position;         // Position at table (0-5)
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
        uint8 dealerPosition;
        uint8 currentPosition;
        uint8 playerCount;
        GameState gameState;
        bool isActive;
        mapping(address => Player) players;
        address[] playerAddresses;
        uint8[] communityCards;
        mapping(address => uint8[]) playerCards;
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
    event BetPlaced(uint256 indexed tableId, address indexed player, uint256 amount);
    event PlayerFolded(uint256 indexed tableId, address indexed player);
    event HandComplete(uint256 indexed tableId, address indexed winner, uint256 pot);
    event CommunityCardsDealt(uint256 indexed tableId, uint8[] cards);
    event TableConfigUpdated(
        uint256 indexed tableId,
        uint256 minBet,
        uint256 maxBet
    );

    // Error messages
    error TableFull();
    error InvalidBuyIn();
    error PlayerNotAtTable();
    error InvalidBetAmount();
    error NotPlayerTurn();
    error InvalidGameState();
    error InsufficientBalance();
    error TableNotActive();
    error InvalidBetLimits();
    error OnlyOwnerAllowed();

    constructor(uint256 _minBetAmount, address payable _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwnerAllowed();
        _;
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

    // Join a table
    function joinTable(uint256 tableId, uint256 buyInAmount) 
        external 
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
            position: uint8(table.playerCount)
        });
        
        table.playerAddresses.push(msg.sender);
        table.playerCount++;
        playerTables[msg.sender] = tableId;
        
        emit PlayerJoined(tableId, msg.sender, buyInAmount);
        
        // Start game if we have enough players
        if (table.playerCount >= 2) {
            startNewHand(tableId);
        }
    }

    // Leave table
    function leaveTable(uint256 tableId) 
        external 
        nonReentrant 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        Table storage table = tables[tableId];
        Player storage player = table.players[msg.sender];
        
        require(player.tableStake > 0, "No stake to withdraw");
        
        // Return stake to treasury
        treasury.processBetWin(msg.sender, player.tableStake);
        
        uint256 remainingStake = player.tableStake;
        player.tableStake = 0;
        player.isActive = false;
        table.playerCount--;
        
        // Remove from playerAddresses
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            if (table.playerAddresses[i] == msg.sender) {
                table.playerAddresses[i] = table.playerAddresses[table.playerAddresses.length - 1];
                table.playerAddresses.pop();
                break;
            }
        }
        
        delete playerTables[msg.sender];
        emit PlayerLeft(tableId, msg.sender, remainingStake);
    }

    // Place bet
    function placeBet(uint256 tableId, uint256 betAmount) 
        external 
        nonReentrant 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        Table storage table = tables[tableId];
        Player storage player = table.players[msg.sender];
        
        require(table.currentPosition == player.position, "Not your turn");
        require(betAmount <= player.tableStake, "Bet exceeds table stake");
        require(betAmount >= table.bigBlind, "Bet below minimum");
        
        player.currentBet = betAmount;
        player.tableStake -= betAmount;
        table.pot += betAmount;
        
        // Move to next active player
        moveToNextPlayer(tableId);
        
        emit BetPlaced(tableId, msg.sender, betAmount);
    }

    // Fold
    function fold(uint256 tableId) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        Table storage table = tables[tableId];
        Player storage player = table.players[msg.sender];
        
        require(table.currentPosition == player.position, "Not your turn");
        
        player.isActive = false;
        moveToNextPlayer(tableId);
        
        emit PlayerFolded(tableId, msg.sender);
    }

    // Internal helper functions
    function startNewHand(uint256 tableId) internal {
        Table storage table = tables[tableId];
        require(table.playerCount >= 2, "Not enough players");
        
        table.gameState = GameState.Dealing;
        table.pot = 0;
        
        // Move dealer button
        table.dealerPosition = (table.dealerPosition + 1) % uint8(table.playerCount);
        
        // Reset player states
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            if (table.players[playerAddr].tableStake > 0) {
                table.players[playerAddr].isActive = true;
                table.players[playerAddr].currentBet = 0;
            }
        }
        
        // Post blinds
        postBlinds(tableId);
        
        table.gameState = GameState.PreFlop;
        emit GameStarted(tableId);
    }

    function postBlinds(uint256 tableId) internal {
        Table storage table = tables[tableId];
        
        // Small blind position
        uint8 sbPos = (table.dealerPosition + 1) % uint8(table.playerCount);
        address sbPlayer = table.playerAddresses[sbPos];
        
        // Big blind position
        uint8 bbPos = (table.dealerPosition + 2) % uint8(table.playerCount);
        address bbPlayer = table.playerAddresses[bbPos];
        
        // Post small blind
        if (table.players[sbPlayer].tableStake >= table.smallBlind) {
            table.players[sbPlayer].tableStake -= table.smallBlind;
            table.players[sbPlayer].currentBet = table.smallBlind;
            table.pot += table.smallBlind;
        }
        
        // Post big blind
        if (table.players[bbPlayer].tableStake >= table.bigBlind) {
            table.players[bbPlayer].tableStake -= table.bigBlind;
            table.players[bbPlayer].currentBet = table.bigBlind;
            table.pot += table.bigBlind;
        }
        
        // Action starts with UTG (Under the Gun)
        table.currentPosition = (bbPos + 1) % uint8(table.playerCount);
    }

    function moveToNextPlayer(uint256 tableId) internal {
        Table storage table = tables[tableId];
        uint8 nextPosition;
        bool foundNext = false;
        
        // Loop through positions until we find next active player
        for (uint8 i = 1; i <= table.playerCount; i++) {
            nextPosition = (table.currentPosition + i) % uint8(table.playerCount);
            address nextPlayer = table.playerAddresses[nextPosition];
            
            if (table.players[nextPlayer].isActive) {
                table.currentPosition = nextPosition;
                foundNext = true;
                break;
            }
        }
        
        // If no active players found, move to next game state
        if (!foundNext) {
            advanceGameState(tableId);
        }
    }

    function advanceGameState(uint256 tableId) internal {
        Table storage table = tables[tableId];
        
        if (table.gameState == GameState.PreFlop) {
            table.gameState = GameState.Flop;
            // Deal flop
        } else if (table.gameState == GameState.Flop) {
            table.gameState = GameState.Turn;
            // Deal turn
        } else if (table.gameState == GameState.Turn) {
            table.gameState = GameState.River;
            // Deal river
        } else if (table.gameState == GameState.River) {
            table.gameState = GameState.Showdown;
            determineWinner(tableId);
        }
    }

    function determineWinner(uint256 tableId) internal {
        // This will be implemented with the game logic for comparing hands
        // For now, it just resets the game
        Table storage table = tables[tableId];
        table.gameState = GameState.Complete;
        
        // Start new hand if enough players
        if (table.playerCount >= 2) {
            startNewHand(tableId);
        } else {
            table.gameState = GameState.Waiting;
        }
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
        uint8 playerCount,
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
        uint8 position
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

    // Add this function to get all players at a table
    function getTablePlayers(uint256 tableId) external view returns (address[] memory) {
        Table storage table = tables[tableId];
        return table.playerAddresses;
    }
}
