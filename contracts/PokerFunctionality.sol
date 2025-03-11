// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IPokerFunctionality.sol";
import "./IPokerTables.sol";
import "./PokerTables.sol";

contract PokerFunctionality is IPokerFunctionality, Ownable, ReentrancyGuard {
    PokerTables public pokerTables;
    
    // Events
    event BetPlaced(uint256 indexed tableId, address indexed player, uint256 amount);
    event PlayerFolded(uint256 indexed tableId, address indexed player);
    event HandComplete(uint256 indexed tableId, address indexed winner, uint256 pot);
    event PlayerCardsDealt(uint256 indexed tableId, address indexed player, uint8[] cards);
    event CommunityCardsDealt(uint256 indexed tableId, uint8[] cards);
    event CardsDealt(uint256 indexed tableId, address indexed player, uint8[] cards);
    event BlindsPosted(uint256 indexed tableId, address smallBlind, address bigBlind, uint256 smallBlindAmount, uint256 bigBlindAmount);
    event HandWinner(uint256 indexed tableId, address indexed winner, IPokerTables.HandRank winningHandRank, uint256 potAmount);
    event TurnStarted(uint256 indexed tableId, address indexed player);
    event TurnEnded(uint256 indexed tableId, address indexed player, string action);
    event RoundComplete(uint256 indexed tableId);

    // Error messages
    error InvalidBetAmount();
    error NotPlayerTurn();
    error InvalidGameState();
    error InsufficientBalance();

    constructor(address _pokerTablesAddress) Ownable(msg.sender) {
        pokerTables = PokerTables(_pokerTablesAddress);
    }
    
    modifier onlyValidTable(uint256 tableId) {
        // This will be replaced by a call to pokerTables
        _;
    }

    modifier onlyTablePlayer(uint256 tableId) {
        // This will be replaced by a call to pokerTables
        _;
    }

    modifier onlyDuringState(uint256 tableId, IPokerTables.GameState state) {
        // This will be replaced by a call to pokerTables
        _;
    }

    // Place bet
    function placeBet(uint256 tableId, uint256 betAmount) 
        external 
        nonReentrant 
        override
    {
        // Implementation will call functions from pokerTables
        emit BetPlaced(tableId, msg.sender, betAmount);
    }

    // Fold
    function fold(uint256 tableId) 
        external 
        override
    {
        // Implementation will call functions from pokerTables
        emit PlayerFolded(tableId, msg.sender);
        emit TurnEnded(tableId, msg.sender, "fold");
    }

    // Check
    function check(uint256 tableId) 
        external 
        override
    {
        // Implementation will call functions from pokerTables
        emit TurnEnded(tableId, msg.sender, "check");
    }

    // Call
    function call(uint256 tableId) 
        external 
        override
    {
        // Implementation will call functions from pokerTables
        emit TurnEnded(tableId, msg.sender, "call");
    }

    // Raise
    function raise(uint256 tableId, uint256 /* amount */) 
        external 
        override
    {
        // Implementation will call functions from pokerTables
        emit TurnEnded(tableId, msg.sender, "raise");
    }

    // Internal helper functions
    function startNewHand(uint256 tableId) external override onlyOwner {
        // Implementation will call functions from pokerTables
    }

    function postBlinds(uint256 tableId) external override onlyOwner {
        // Implementation will call functions from pokerTables
    }

    function startFlop(uint256 tableId) external override onlyOwner {
        // Implementation will call functions from pokerTables
    }

    function startTurn(uint256 tableId) external override onlyOwner {
        // Implementation will call functions from pokerTables
    }

    function startRiver(uint256 tableId) external override onlyOwner {
        // Implementation will call functions from pokerTables
    }

    function startShowdown(uint256 tableId) external override onlyOwner {
        // Implementation will call functions from pokerTables
    }

    function moveToNextPlayer(uint256 tableId) internal {
        // Implementation will call functions from pokerTables
    }

    function advanceGameState(uint256 tableId) internal {
        // Implementation will call functions from pokerTables
    }

    function determineWinner(uint256 tableId) internal {
        // Implementation will call functions from pokerTables
    }

    // View functions
    function getPlayerCards(uint256 /* tableId */, address /* player */) 
        external 
        pure
        override
        returns (uint8[] memory) 
    {
        // Implementation will call functions from pokerTables
        return new uint8[](0);
    }

    function getCommunityCards(uint256 /* tableId */) 
        external 
        pure
        override
        returns (uint8[] memory) 
    {
        // Implementation will call functions from pokerTables
        return new uint8[](0);
    }

    // Helper function to evaluate poker hands
    function evaluateHand(uint8[] memory cards) internal pure returns (IPokerTables.HandRank, uint256) {
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
            return (IPokerTables.HandRank.RoyalFlush, score);
        }

        // Check for straight flush
        if (isFlush && isStraight) {
            return (IPokerTables.HandRank.StraightFlush, score);
        }

        // Check for four of a kind
        if (maxFreq == 4) {
            return (IPokerTables.HandRank.FourOfAKind, uint256(highestValue) * 100 + uint256(values[0]));
        }

        // Check for full house
        if (maxFreq == 3 && secondMaxFreq == 2) {
            return (IPokerTables.HandRank.FullHouse, uint256(highestValue) * 100 + uint256(secondHighestValue));
        }

        // Check for flush
        if (isFlush) {
            return (IPokerTables.HandRank.Flush, score);
        }

        // Check for straight
        if (isStraight) {
            return (IPokerTables.HandRank.Straight, score);
        }

        // Check for three of a kind
        if (maxFreq == 3) {
            return (IPokerTables.HandRank.ThreeOfAKind, uint256(highestValue) * 100 + score);
        }

        // Check for two pair
        if (maxFreq == 2 && secondMaxFreq == 2) {
            return (IPokerTables.HandRank.TwoPair, uint256(highestValue) * 100 + uint256(secondHighestValue) * 10 + uint256(values[4]));
        }

        // Check for pair
        if (maxFreq == 2) {
            return (IPokerTables.HandRank.Pair, uint256(highestValue) * 100 + score);
        }

        // High card
        return (IPokerTables.HandRank.HighCard, score);
    }

    // Internal helper functions for game state
    function resetRound(uint256 tableId) internal {
        // Implementation will call functions from pokerTables
    }

    function checkRoundComplete(uint256 /* tableId */) internal pure returns (bool) {
        // Implementation will call functions from pokerTables
        return false;
    }

    function dealPlayerCards(uint256 tableId, address player, uint8[] memory cards) internal {
        // Implementation will call functions from pokerTables
    }

    function dealCommunityCards(uint256 tableId, uint8[] memory cards) internal {
        // Implementation will call functions from pokerTables
    }
} 