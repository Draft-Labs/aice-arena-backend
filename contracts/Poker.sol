// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;
import "hardhat/console.sol";
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
    event HandWinner(uint256 indexed tableId, address indexed winner, HandRank winningHandRank, uint256 potAmount);
    event TurnStarted(uint256 indexed tableId, address indexed player);
    event TurnEnded(uint256 indexed tableId, address indexed player, string action);
    event RoundComplete(uint256 indexed tableId);

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
            position: uint256(table.playerCount)
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
        // Log initial state
        console.log("=== Starting fold operation ===");
        console.log("Table ID:", tableId);
        console.log("Sender:", msg.sender);
        
        Table storage table = tables[tableId];
        console.log("Table loaded. Player count:", table.playerCount);
        console.log("Current position:", table.currentPosition);
        
        Player storage player = table.players[msg.sender];
        console.log("Player loaded. Position:", player.position);
        console.log("Player active status:", player.isActive);
        
        // Basic checks
        console.log("Performing checks...");
        require(table.currentPosition == player.position, "Not your turn");
        require(player.isActive, "Player not active");
        require(player.position < table.playerAddresses.length, "Invalid player position");
        require(table.playerCount > 0, "No players at table");
        console.log("Basic checks passed");
        
        // Count active players before fold
        uint256 activeBefore = 0;
        console.log("Counting active players...");
        console.log("Player addresses length:", table.playerAddresses.length);
        
        for (uint256 i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            console.log("Checking player", i, ":", playerAddr);
            if (table.players[playerAddr].isActive) {
                activeBefore++;
                console.log("Player", i, "is active");
            }
        }
        
        console.log("Active players count:", activeBefore);
        require(activeBefore > 1, "Not enough active players");
        
        // Perform fold
        console.log("Performing fold...");
        player.isActive = false;
        table.hasActed[player.position] = true;
        console.log("Player marked as inactive");
        
        emit PlayerFolded(tableId, msg.sender);
        emit TurnEnded(tableId, msg.sender, "fold");
        
        // Find next player
        console.log("Finding next player...");
        moveToNextPlayer(tableId);
        console.log("=== Fold operation complete ===");
    }

    // Internal helper functions
    function startNewHand(uint256 tableId) internal {
        Table storage table = tables[tableId];
        
        // Reset game state
        table.gameState = GameState.Dealing;
        table.pot = 0;
        table.currentBet = 0;
        table.currentPosition = 0;
        table.roundComplete = false;
        
        // Reset hasActed mapping
        for (uint256 i = 0; i < table.playerCount; i++) {
            table.hasActed[i] = false;
        }
        
        // Clear existing cards
        delete table.communityCards;
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address player = table.playerAddresses[i];
            delete table.playerCards[player];
        }

        // Reactivate all players
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            table.players[table.playerAddresses[i]].isActive = true;
        }
        
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

        //Start the turn for player 0
        emit TurnStarted(tableId, table.playerAddresses[0]);
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
        console.log("=== Starting moveToNextPlayer ===");
        Table storage table = tables[tableId];
        console.log("Current position:", table.currentPosition);
        console.log("Player count:", table.playerCount);
        console.log("Player addresses length:", table.playerAddresses.length);
        
        require(table.playerCount > 0, "No players at table");
        require(table.playerAddresses.length > 0, "No player addresses");
        require(table.currentPosition < table.playerAddresses.length, "Invalid current position");
        
        bool foundNext = false;
        uint256 startingPosition = table.currentPosition;
        
        console.log("Starting position:", startingPosition);
        
        // Try to find next active player
        for (uint256 i = 1; i <= table.playerAddresses.length; i++) {
            uint256 nextPosition = (startingPosition + i) % table.playerAddresses.length;
            console.log("Checking position:", nextPosition);
            
            address nextPlayer = table.playerAddresses[nextPosition];
            console.log("Next player address:", nextPlayer);
            
            if (nextPlayer != address(0) && table.players[nextPlayer].isActive) {
                table.currentPosition = nextPosition;
                foundNext = true;
                console.log("Found next player at position:", nextPosition);
                emit TurnStarted(tableId, nextPlayer);
                break;
            }
        }
        
        console.log("Found next:", foundNext);
        console.log("Round complete:", checkRoundComplete(tableId));
        
        if (!foundNext || checkRoundComplete(tableId)) {
            console.log("Advancing game state");
            advanceGameState(tableId);
        }
        console.log("=== moveToNextPlayer complete ===");
    }

    function advanceGameState(uint256 tableId) internal {
        Table storage table = tables[tableId];

        // Require that all players have acted
        require(checkRoundComplete(tableId), "Not all players have acted");
        
        // Reset all hasActed flags and current bets for the new round
        resetRound(tableId);
        
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
        Table storage table = tables[tableId];
        
        // Find player with highest hand
        address winner;
        HandRank highestRank = HandRank.HighCard;
        uint256 highestScore = 0;
        
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            if (table.players[playerAddr].isActive) {
                // Get player's cards
                uint8[] memory playerCards = table.playerCards[playerAddr];
                uint8[] memory allCards = new uint8[](7);
                
                // Combine player cards and community cards
                allCards[0] = playerCards[0];
                allCards[1] = playerCards[1];
                for(uint j = 0; j < table.communityCards.length; j++) {
                    allCards[j + 2] = table.communityCards[j];
                }
                
                // Evaluate hand
                (HandRank rank, uint256 score) = evaluateHand(allCards);
                
                // Update winner if this hand is better
                if (winner == address(0) || 
                    uint8(rank) > uint8(highestRank) || 
                    (uint8(rank) == uint8(highestRank) && score > highestScore)) {
                    winner = playerAddr;
                    highestRank = rank;
                    highestScore = score;
                    
                    console.log("New best hand found:");
                    console.log("Player:", winner);
                    console.log("Rank:", uint8(rank));
                    console.log("Score:", score);
                }
            }
        }
        
        // Award pot to winner
        if (winner != address(0)) {
            uint256 potAmount = table.pot;
            table.pot = 0;
            table.players[winner].tableStake += potAmount;
            
            // Emit events
            emit HandComplete(tableId, winner, potAmount);
            emit HandWinner(tableId, winner, highestRank, potAmount);
        }
        
        table.gameState = GameState.Complete;
        
        // Start new hand if enough players
        if (table.playerCount >= 2) {
            startNewHand(tableId);
        } else {
            table.gameState = GameState.Waiting;
        }
    }

    // Add this helper function to evaluate poker hands
    function evaluateHand(uint8[] memory cards) internal pure returns (HandRank, uint256) {
        // Convert card numbers to values (1-13) and suits (0-3)
        uint8[] memory values = new uint8[](cards.length);
        uint8[] memory suits = new uint8[](cards.length);
        for (uint i = 0; i < cards.length; i++) {
            values[i] = ((cards[i] - 1) % 13) + 1;
            suits[i] = (cards[i] - 1) / 13;
        }
        
        // Sort values in descending order (bubble sort)
        for (uint i = 0; i < values.length - 1; i++) {
            for (uint j = 0; j < values.length - i - 1; j++) {
                if (values[j] < values[j + 1]) {
                    // Swap values
                    uint8 tempValue = values[j];
                    values[j] = values[j + 1];
                    values[j + 1] = tempValue;
                    // Swap corresponding suits
                    uint8 tempSuit = suits[j];
                    suits[j] = suits[j + 1];
                    suits[j + 1] = tempSuit;
                }
            }
        }

        // Check for flush
        bool isFlush = true;
        uint8 firstSuit = suits[0];
        for (uint i = 1; i < suits.length; i++) {
            if (suits[i] != firstSuit) {
                isFlush = false;
                break;
            }
        }

        // Check for straight
        bool isStraight = true;
        for (uint i = 0; i < values.length - 1; i++) {
            if (values[i] != values[i + 1] + 1) {
                // Special case for Ace-low straight (A,5,4,3,2)
                if (!(i == 0 && values[0] == 14 && values[1] == 5)) {
                    isStraight = false;
                    break;
                }
            }
        }

        // Count card frequencies
        uint8[14] memory freq; // Index 0 unused, 1-13 for card values
        for (uint i = 0; i < values.length; i++) {
            freq[values[i]]++;
        }

        // Find highest frequency and pairs
        uint8 maxFreq = 0;
        uint8 secondMaxFreq = 0;
        uint8 highestValue = 0;
        uint8 secondHighestValue = 0;

        for (uint8 i = 13; i >= 1; i--) {
            if (freq[i] >= maxFreq) {
                secondMaxFreq = maxFreq;
                secondHighestValue = highestValue;
                maxFreq = freq[i];
                highestValue = i;
            } else if (freq[i] > secondMaxFreq) {
                secondMaxFreq = freq[i];
                secondHighestValue = i;
            }
            if (i == 1) break; // Prevent underflow
        }

        // Calculate base score using highest cards (prevent overflow)
        uint256 score = uint256(values[0]) * 100 + uint256(values[1]) * 10 + uint256(values[2]);

        // Check for royal flush
        if (isFlush && isStraight && values[0] == 14 && values[1] == 13) {
            return (HandRank.RoyalFlush, score);
        }

        // Check for straight flush
        if (isFlush && isStraight) {
            return (HandRank.StraightFlush, score);
        }

        // Check for four of a kind
        if (maxFreq == 4) {
            return (HandRank.FourOfAKind, uint256(highestValue) * 100 + uint256(values[0]));
        }

        // Check for full house
        if (maxFreq == 3 && secondMaxFreq == 2) {
            return (HandRank.FullHouse, uint256(highestValue) * 100 + uint256(secondHighestValue));
        }

        // Check for flush
        if (isFlush) {
            return (HandRank.Flush, score);
        }

        // Check for straight
        if (isStraight) {
            return (HandRank.Straight, score);
        }

        // Check for three of a kind
        if (maxFreq == 3) {
            return (HandRank.ThreeOfAKind, uint256(highestValue) * 100 + score);
        }

        // Check for two pair
        if (maxFreq == 2 && secondMaxFreq == 2) {
            return (HandRank.TwoPair, uint256(highestValue) * 100 + uint256(secondHighestValue) * 10 + uint256(values[4]));
        }

        // Check for pair
        if (maxFreq == 2) {
            return (HandRank.Pair, uint256(highestValue) * 100 + score);
        }

        // High card
        return (HandRank.HighCard, score);
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
        require(player.currentBet == table.currentBet, "Cannot check");
        
        table.hasActed[player.position] = true;
        
        emit TurnEnded(tableId, msg.sender, "check");
        moveToNextPlayer(tableId);
    }

    function call(uint256 tableId) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        Table storage table = tables[tableId];
        Player storage player = table.players[msg.sender];
        
        require(table.currentPosition == player.position, "Not your turn");
        
        uint256 callAmount = table.currentBet - player.currentBet;
        require(callAmount <= player.tableStake, "Insufficient funds");
        
        player.tableStake -= callAmount;
        player.currentBet = table.currentBet;
        table.pot += callAmount;
        table.hasActed[player.position] = true;
        
        emit BetPlaced(tableId, msg.sender, callAmount);
        emit TurnEnded(tableId, msg.sender, "call");
        
        moveToNextPlayer(tableId);
    }

    function startFlop(uint256 tableId) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.PreFlop, "Not in PreFlop state");
        require(checkRoundComplete(tableId), "Not all players have acted");
        
        
        // Deal flop cards
        uint8[] memory flopCards = new uint8[](3);
        flopCards[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop1"))) % 52 + 1);
        flopCards[1] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop2"))) % 52 + 1);
        flopCards[2] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop3"))) % 52 + 1);
        
        // Store cards directly
        table.communityCards = flopCards;
        
        // Change game state
        table.gameState = GameState.Flop;
        
        emit CommunityCardsDealt(tableId, flopCards);
    }

    function startTurn(uint256 tableId) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.Flop, "Not in Flop state");
        require(checkRoundComplete(tableId), "Not all players have acted");

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
        require(checkRoundComplete(tableId), "Not all players have acted");

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
        require(checkRoundComplete(tableId), "Not all players have acted");

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
        
        // Log before award
        console.log("Awarding pot to winner:", winner);
        console.log("Pot amount:", table.pot);
        
        // Add pot to winner's table stake
        player.tableStake += table.pot;
        
        // Reset pot
        uint256 potAmount = table.pot;
        table.pot = 0;
        
        // Get winner's hand rank
        uint8[] memory playerCards = table.playerCards[winner];
        uint8[] memory allCards = new uint8[](7);
        
        // Combine player cards and community cards
        allCards[0] = playerCards[0];
        allCards[1] = playerCards[1];
        for(uint j = 0; j < table.communityCards.length; j++) {
            allCards[j + 2] = table.communityCards[j];
        }
        
        // Evaluate hand
        (HandRank winningRank, ) = evaluateHand(allCards);
        
        // Log after award
        console.log("Pot awarded, emitting event");
        
        // Only emit HandComplete for game state tracking
        emit HandComplete(tableId, winner, potAmount);
        // Emit HandWinner with the actual hand rank
        emit HandWinner(tableId, winner, winningRank, potAmount);
        
        console.log("Events emitted");
    }

    function checkRoundComplete(uint256 tableId) internal view returns (bool) {
        Table storage table = tables[tableId];
        uint256 activeCount = 0;
        uint256 targetBet = table.currentBet;
        
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            Player storage player = table.players[playerAddr];
            
            if (player.isActive) {
                activeCount++;
                if (!table.hasActed[i] || player.currentBet != targetBet) {
                    return false;
                }
            }
        }
        
        return activeCount >= 2;
    }

    function raise(uint256 tableId, uint256 amount) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        Table storage table = tables[tableId];
        Player storage player = table.players[msg.sender];
        
        require(table.currentPosition == player.position, "Not your turn");
        require(amount > table.currentBet * 2, "Raise must be at least double current bet");
        require(amount <= player.tableStake, "Insufficient funds");
        require(amount >= table.minBet && amount <= table.maxBet, "Invalid bet amount");
        
        player.tableStake -= amount;
        player.currentBet = amount;
        table.currentBet = amount;
        table.pot += amount;
        table.hasActed[player.position] = true;
        
        // Reset hasActed for all other players since they need to respond to raise
        for (uint256 i = 0; i < table.playerCount; i++) {
            if (i != player.position) {
                table.hasActed[i] = false;
            }
        }
        
        emit BetPlaced(tableId, msg.sender, amount);
        emit TurnEnded(tableId, msg.sender, "raise");
        
        moveToNextPlayer(tableId);
    }

    // Add this new helper function
    function resetRound(uint256 tableId) internal {
        Table storage table = tables[tableId];
        
        // Reset hasActed flags
        for (uint256 i = 0; i < table.playerCount; i++) {
            table.hasActed[i] = false;
        }
        
        // Only reset current bets if the hand is complete
        if (table.gameState == GameState.Complete || table.gameState == GameState.Waiting) {
            // Reset current bets
            for (uint i = 0; i < table.playerAddresses.length; i++) {
                address playerAddr = table.playerAddresses[i];
                if (table.players[playerAddr].isActive) {
                    table.players[playerAddr].currentBet = 0;
                }
            }
            
            // Reset table current bet
            table.currentBet = 0;
        }
        
        // Reset current position to first active player
        for (uint256 i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            if (table.players[playerAddr].isActive) {
                table.currentPosition = i;
                break;
            }
        }
    }
}
