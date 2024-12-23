// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./HouseTreasury.sol";

contract Poker is Ownable, ReentrancyGuard {
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
        uint256 currentBet;
        uint8 dealerPosition;
        uint8 currentPosition;
        uint8 playerCount;
        GameState gameState;
        bool isActive;
        mapping(address => Player) players;
        address[] playerAddresses;
        uint8[] communityCards;
        mapping(address => uint8[]) playerCards;
        mapping(uint8 => bool) hasActed;
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
    event BetPlaced(uint256 indexed tableId, address indexed player, uint256 amount);
    event PlayerFolded(uint256 indexed tableId, address indexed player);
    event HandComplete(uint256 indexed tableId, address indexed winner, uint256 pot);
    event TableConfigUpdated(
        uint256 indexed tableId,
        uint256 minBet,
        uint256 maxBet
    );
    event PlayerCardsDealt(uint256 indexed tableId, address indexed player, uint8[] cards);
    event CommunityCardsDealt(uint256 indexed tableId, uint8[] cards);
    event CardsDealt(uint256 indexed tableId, address indexed player, uint8[] cards);
    event BlindsPosted(uint256 indexed tableId, address smallBlind, address bigBlind, uint256 smallBlindAmount, uint256 bigBlindAmount);

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
    function fold(uint256 tableId) external {
        Table storage table = tables[tableId];
        require(table.gameState != GameState.Waiting, "Game not started");
        
        Player storage player = table.players[msg.sender];
        require(player.isActive, "Player not active");
        require(table.currentPosition == player.position, "Not your turn");
        
        player.isActive = false;
        table.hasActed[player.position] = true;
        
        // Move to next player
        moveToNextPlayer(tableId);
        
        emit PlayerFolded(tableId, msg.sender);
        
        // Check if only one player remains
        checkWinner(tableId);
    }

    // Internal helper functions
    function startNewHand(uint256 tableId) internal {
        Table storage table = tables[tableId];
        
        // Clear community cards
        delete table.communityCards;
        
        // Clear player cards
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address player = table.playerAddresses[i];
            delete table.playerCards[player];
        }
        
        // Reset game state
        table.gameState = GameState.Dealing;
        table.pot = 0;
        
        // Deal new cards to active players
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address player = table.playerAddresses[i];
            if (table.players[player].isActive) {
                uint8[] memory cards = new uint8[](2);
                cards[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, player, "card1"))) % 52 + 1);
                cards[1] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, player, "card2"))) % 52 + 1);
                dealPlayerCards(tableId, player, cards);
            }
        }
        
        // Move to PreFlop state
        table.gameState = GameState.PreFlop;
    }

    function postBlinds(uint256 tableId) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.PreFlop, "Not in PreFlop state");
        
        // Get players directly from storage
        address[] storage tablePlayers = table.playerAddresses;
        require(tablePlayers.length >= 2, "Need at least 2 players");
        
        // Post small blind (Player 0)
        address smallBlindPlayer = tablePlayers[0];
        uint256 smallBlindAmount = table.smallBlind;
        Player storage smallBlindPlayerInfo = table.players[smallBlindPlayer];
        require(smallBlindPlayerInfo.tableStake >= smallBlindAmount, "Small blind cannot cover bet");
        smallBlindPlayerInfo.tableStake -= smallBlindAmount;
        smallBlindPlayerInfo.currentBet = smallBlindAmount;
        table.pot += smallBlindAmount;
        
        // Post big blind (Player 1)
        address bigBlindPlayer = tablePlayers[1];
        uint256 bigBlindAmount = table.bigBlind;
        Player storage bigBlindPlayerInfo = table.players[bigBlindPlayer];
        require(bigBlindPlayerInfo.tableStake >= bigBlindAmount, "Big blind cannot cover bet");
        bigBlindPlayerInfo.tableStake -= bigBlindAmount;
        bigBlindPlayerInfo.currentBet = bigBlindAmount;
        table.pot += bigBlindAmount;
        
        // Update current bet to big blind amount
        table.currentBet = bigBlindAmount;
        
        emit BlindsPosted(tableId, smallBlindPlayer, bigBlindPlayer, smallBlindAmount, bigBlindAmount);
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
            // Deal flop cards
            uint8[] memory flopCards = new uint8[](3);
            flopCards[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop1"))) % 52 + 1);
            flopCards[1] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop2"))) % 52 + 1);
            flopCards[2] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop3"))) % 52 + 1);
            dealCommunityCards(tableId, flopCards);
        } else if (table.gameState == GameState.Flop) {
            table.gameState = GameState.Turn;
            // Deal turn card
            uint8[] memory turnCard = new uint8[](1);
            turnCard[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "turn"))) % 52 + 1);
            dealCommunityCards(tableId, turnCard);
        } else if (table.gameState == GameState.Turn) {
            table.gameState = GameState.River;
            // Deal river card
            uint8[] memory riverCard = new uint8[](1);
            riverCard[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "river"))) % 52 + 1);
            dealCommunityCards(tableId, riverCard);
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

    function check(uint256 tableId) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        Table storage table = tables[tableId];
        Player storage player = table.players[msg.sender];
        
        require(table.currentPosition == player.position, "Not your turn");
        require(player.currentBet == table.minBet, "Cannot check");
        
        moveToNextPlayer(tableId);
    }

    function call(uint256 tableId) external {
        Table storage table = tables[tableId];
        require(table.gameState != GameState.Waiting, "Game not started");
        
        Player storage player = table.players[msg.sender];
        require(player.isActive, "Player not active");
        require(table.currentPosition == player.position, "Not your turn");
        
        uint256 callAmount = table.currentBet - player.currentBet;
        require(callAmount <= player.tableStake, "Insufficient funds");
        
        // Update bets
        player.tableStake -= callAmount;
        player.currentBet = table.currentBet;
        table.pot += callAmount;
        table.hasActed[player.position] = true;
        
        // Move to next player
        moveToNextPlayer(tableId);
        
        emit BetPlaced(tableId, msg.sender, callAmount);
    }

    function startFlop(uint256 tableId) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.PreFlop, "Not in PreFlop state");
        
        // Post blinds first
        address[] storage tablePlayers = table.playerAddresses;
        require(tablePlayers.length >= 2, "Need at least 2 players");
        
        // Post small blind (Player 0)
        address smallBlindPlayer = tablePlayers[0];
        uint256 smallBlindAmount = table.smallBlind;
        Player storage smallBlindPlayerInfo = table.players[smallBlindPlayer];
        require(smallBlindPlayerInfo.tableStake >= smallBlindAmount, "Small blind cannot cover bet");
        smallBlindPlayerInfo.tableStake -= smallBlindAmount;
        smallBlindPlayerInfo.currentBet = smallBlindAmount;
        table.pot += smallBlindAmount;
        
        // Post big blind (Player 1)
        address bigBlindPlayer = tablePlayers[1];
        uint256 bigBlindAmount = table.bigBlind;
        Player storage bigBlindPlayerInfo = table.players[bigBlindPlayer];
        require(bigBlindPlayerInfo.tableStake >= bigBlindAmount, "Big blind cannot cover bet");
        bigBlindPlayerInfo.tableStake -= bigBlindAmount;
        bigBlindPlayerInfo.currentBet = bigBlindAmount;
        table.pot += bigBlindAmount;
        
        // Update current bet to big blind amount
        table.currentBet = bigBlindAmount;
        
        // Deal flop cards
        uint8[] memory flopCards = new uint8[](3);
        flopCards[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop1"))) % 52 + 1);
        flopCards[1] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop2"))) % 52 + 1);
        flopCards[2] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop3"))) % 52 + 1);
        
        // Store cards directly
        table.communityCards = flopCards;
        
        // Change game state
        table.gameState = GameState.Flop;
        
        emit BlindsPosted(tableId, smallBlindPlayer, bigBlindPlayer, smallBlindAmount, bigBlindAmount);
        emit CommunityCardsDealt(tableId, flopCards);
    }

    function startTurn(uint256 tableId) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.Flop, "Not in Flop state");
        
        // Deal turn card
        uint8 turnCard = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "turn"))) % 52 + 1);
        
        // Add turn card to community cards
        table.communityCards.push(turnCard);
        
        // Change game state
        table.gameState = GameState.Turn;
        
        emit CommunityCardsDealt(tableId, table.communityCards);
    }

    function startRiver(uint256 tableId) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.Turn, "Not in Turn state");
        
        // Deal river card
        uint8 riverCard = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "river"))) % 52 + 1);
        
        // Add river card to community cards
        table.communityCards.push(riverCard);
        
        // Change game state
        table.gameState = GameState.River;
        
        emit CommunityCardsDealt(tableId, table.communityCards);
    }

    function startShowdown(uint256 tableId) 
        external 
        onlyOwner 
        onlyValidTable(tableId) 
    {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.River, "Invalid game state");
        
        table.gameState = GameState.Showdown;
        determineWinner(tableId);
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
        internal 
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
        internal 
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
        require(msg.sender == player || msg.sender == owner(), "Not authorized");
        return tables[tableId].playerCards[player];
    }

    function getCommunityCards(uint256 tableId) 
        public 
        view 
        returns (uint8[] memory) 
    {
        return tables[tableId].communityCards;
    }

    // Internal helper function
    function _placeBet(uint256 tableId, address player, uint256 amount) internal {
        Table storage table = tables[tableId];
        Player storage playerInfo = table.players[player];
        
        require(playerInfo.tableStake >= amount, "Insufficient balance");
        
        playerInfo.tableStake -= amount;
        playerInfo.currentBet = amount;
        table.pot += amount;
        
        emit BetPlaced(tableId, player, amount);
    }

    function _awardPot(uint256 tableId, address winner) internal {
        Table storage table = tables[tableId];
        Player storage player = table.players[winner];
        
        // Add pot to winner's table stake
        player.tableStake += table.pot;
        
        // Reset pot
        uint256 potAmount = table.pot;
        table.pot = 0;
        
        emit HandComplete(tableId, winner, potAmount);
    }

    function isBettingRoundComplete(uint256 tableId) internal view returns (bool) {
        Table storage table = tables[tableId];
        uint8 activeCount = 0;
        uint256 targetBet = table.currentBet;
        
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            Player storage player = table.players[playerAddr];
            
            if (player.isActive) {
                activeCount++;
                if (!table.hasActed[player.position] || player.currentBet != targetBet) {
                    return false;
                }
            }
        }
        
        return activeCount >= 2;
    }

    function raise(uint256 tableId, uint256 amount) external {
        Table storage table = tables[tableId];
        require(table.gameState != GameState.Waiting, "Game not started");
        
        Player storage player = table.players[msg.sender];
        require(player.isActive, "Player not active");
        require(table.currentPosition == player.position, "Not your turn");
        require(amount >= table.currentBet * 2, "Raise must be at least double current bet");
        require(amount <= player.tableStake, "Insufficient funds");
        
        // Update bets
        player.tableStake -= amount;
        player.currentBet = amount;
        table.currentBet = amount;
        table.pot += amount;
        table.hasActed[player.position] = true;
        
        // Move to next player
        moveToNextPlayer(tableId);
        
        emit BetPlaced(tableId, msg.sender, amount);
    }

    function checkWinner(uint256 tableId) internal {
        Table storage table = tables[tableId];
        uint8 activeCount = 0;
        address winner;
        
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            if (table.players[playerAddr].isActive) {
                activeCount++;
                winner = playerAddr;
            }
        }
        
        if (activeCount == 1) {
            _awardPot(tableId, winner);
            table.gameState = GameState.Complete;
        }
    }
}
