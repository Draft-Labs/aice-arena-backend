// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./HouseTreasury.sol";

contract Balatro is ReentrancyGuard {
    address public owner;
    HouseTreasury public treasury;
    uint256 public minBetAmount;
    
    // Game state enums
    enum GameState { Waiting, InProgress, Completed }
    enum CardSuit { Hearts, Diamonds, Clubs, Spades, Joker }
    
    // Card structure
    struct Card {
        uint8 rank;  // 1-13 (Ace=1, Jack=11, Queen=12, King=13), 0 for Joker
        CardSuit suit;
        bool isJoker;
        uint256 multiplier;  // Base multiplier for special cards
    }
    
    // Hand structure
    struct Hand {
        Card[] cards;
        uint256 bet;
        uint256 multiplier;
        bool isActive;
    }
    
    // Game structure
    struct Game {
        address player;
        GameState state;
        Hand[] hands;
        uint256 totalMultiplier;
        uint256 roundNumber;
        uint256 score;
    }
    
    // Mapping of active games
    mapping(address => Game) public games;
    mapping(address => bool) public isPlayerActive;
    address[] private activePlayers;
    
    // Events
    event GameStarted(address indexed player, uint256 bet);
    event CardDrawn(address indexed player, uint8 rank, CardSuit suit);
    event HandCompleted(address indexed player, uint256 multiplier, uint256 score);
    event GameCompleted(address indexed player, uint256 totalScore, uint256 winnings);
    
    // Errors
    error InsufficientBet();
    error GameAlreadyInProgress();
    error NoActiveGame();
    error InvalidGameState();
    error InsufficientTreasuryBalance();
    
    constructor(uint256 _minBetAmount, address payable _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyActiveGame() {
        if (!isPlayerActive[msg.sender]) revert NoActiveGame();
        _;
    }
    
    // Start a new game
    function startGame() external payable nonReentrant {
        if (msg.value < minBetAmount) revert InsufficientBet();
        if (isPlayerActive[msg.sender]) revert GameAlreadyInProgress();
        
        // Check if treasury has enough funds for potential max win
        if (treasury.getHouseFunds() < msg.value * 100) // Assuming max multiplier of 100x
            revert InsufficientTreasuryBalance();
            
        // Initialize new game
        Game storage game = games[msg.sender];
        game.player = msg.sender;
        game.state = GameState.InProgress;
        game.roundNumber = 1;
        game.score = 0;
        game.totalMultiplier = 1;
        
        // Clear previous hands if any
        delete game.hands;
        
        // Add initial hand
        Hand memory newHand;
        newHand.bet = msg.value;
        newHand.multiplier = 1;
        newHand.isActive = true;
        game.hands.push(newHand);
        
        // Add to active players
        isPlayerActive[msg.sender] = true;
        activePlayers.push(msg.sender);
        
        // Transfer bet to treasury
        (bool success, ) = address(treasury).call{value: msg.value}("");
        require(success, "Failed to transfer bet to treasury");
        
        emit GameStarted(msg.sender, msg.value);
    }
    
    // Draw a card for the current hand
    function drawCard() external onlyActiveGame {
        Game storage game = games[msg.sender];
        if (game.state != GameState.InProgress) revert InvalidGameState();
        
        // Get current hand
        require(game.hands.length > 0, "No active hands");
        Hand storage currentHand = game.hands[game.hands.length - 1];
        
        // Generate pseudo-random card
        uint256 randomValue = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender,
            game.roundNumber,
            currentHand.cards.length
        )));
        
        // Create new card
        Card memory newCard;
        newCard.rank = uint8((randomValue % 13) + 1);
        newCard.suit = CardSuit(uint8(randomValue % 4));
        newCard.isJoker = false;
        newCard.multiplier = 1;
        
        // Small chance for Joker (1%)
        if (randomValue % 100 == 0) {
            newCard.isJoker = true;
            newCard.suit = CardSuit.Joker;
            newCard.rank = 0;
            newCard.multiplier = 2;  // Base Joker multiplier
        }
        
        // Add card to hand
        currentHand.cards.push(newCard);
        
        emit CardDrawn(msg.sender, newCard.rank, newCard.suit);
    }
    
    // Complete current hand and calculate score
    function completeHand() external onlyActiveGame {
        Game storage game = games[msg.sender];
        require(game.hands.length > 0, "No active hands");
        
        Hand storage currentHand = game.hands[game.hands.length - 1];
        require(currentHand.cards.length >= 5, "Not enough cards in hand");
        
        // Calculate hand multiplier based on poker hand ranking and special cards
        uint256 handMultiplier = calculateHandMultiplier(currentHand);
        currentHand.multiplier = handMultiplier;
        game.totalMultiplier *= handMultiplier;
        
        // Update game score
        uint256 handScore = currentHand.bet * handMultiplier;
        game.score += handScore;
        
        emit HandCompleted(msg.sender, handMultiplier, handScore);
        
        // Move to next round or complete game
        if (game.roundNumber >= 3) {
            completeGame();
        } else {
            game.roundNumber++;
            // Start new hand with current score as bet
            Hand memory newHand;
            newHand.bet = game.score;
            newHand.multiplier = 1;
            newHand.isActive = true;
            game.hands.push(newHand);
        }
    }
    
    // Internal function to calculate hand multiplier
    function calculateHandMultiplier(Hand memory hand) internal pure returns (uint256) {
        uint256 baseMultiplier = 1;
        
        // Count ranks and suits
        uint8[14] memory rankCounts;  // 0 for Joker, 1-13 for regular cards
        uint8[5] memory suitCounts;   // Include Joker suit
        
        for (uint256 i = 0; i < hand.cards.length; i++) {
            Card memory card = hand.cards[i];
            if (card.isJoker) {
                rankCounts[0]++;
                suitCounts[uint8(CardSuit.Joker)]++;
            } else {
                rankCounts[card.rank]++;
                suitCounts[uint8(card.suit)]++;
            }
        }
        
        // Check for poker hands (simplified version)
        bool hasPair = false;
        bool hasThreeOfAKind = false;
        bool hasFourOfAKind = false;
        bool hasFlush = false;
        bool hasStraight = false;
        
        // Check pairs, three of a kind, four of a kind
        for (uint8 i = 1; i <= 13; i++) {
            if (rankCounts[i] == 2) hasPair = true;
            if (rankCounts[i] == 3) hasThreeOfAKind = true;
            if (rankCounts[i] == 4) hasFourOfAKind = true;
        }
        
        // Check flush
        for (uint8 i = 0; i < 4; i++) {
            if (suitCounts[i] >= 5) hasFlush = true;
        }
        
        // Apply multipliers
        if (hasFourOfAKind) baseMultiplier *= 10;
        else if (hasThreeOfAKind && hasPair) baseMultiplier *= 7;  // Full house
        else if (hasFlush) baseMultiplier *= 6;
        else if (hasStraight) baseMultiplier *= 5;
        else if (hasThreeOfAKind) baseMultiplier *= 4;
        else if (hasPair) baseMultiplier *= 2;
        
        // Apply Joker multipliers
        baseMultiplier *= (2 ** rankCounts[0]);  // Double for each Joker
        
        return baseMultiplier;
    }
    
    // Complete the game and process winnings
    function completeGame() internal {
        Game storage game = games[msg.sender];
        uint256 winnings = game.score;
        
        // Process winnings through treasury
        if (winnings > 0) {
            treasury.processBetWin(msg.sender, winnings);
        }
        
        // Clean up game state
        game.state = GameState.Completed;
        isPlayerActive[msg.sender] = false;
        
        // Remove from active players
        for (uint256 i = 0; i < activePlayers.length; i++) {
            if (activePlayers[i] == msg.sender) {
                activePlayers[i] = activePlayers[activePlayers.length - 1];
                activePlayers.pop();
                break;
            }
        }
        
        emit GameCompleted(msg.sender, game.score, winnings);
    }
    
    // View functions
    function getActiveGame() external view returns (Game memory) {
        return games[msg.sender];
    }
    
    function getActivePlayers() external view returns (address[] memory) {
        return activePlayers;
    }
}
