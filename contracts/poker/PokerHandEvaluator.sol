// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PokerHandEvaluator
 * @dev Library for evaluating poker hands
 */
library PokerHandEvaluator {
    // Hand rankings
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

    struct Card {
        uint8 suit;   // 0-3 (Hearts, Diamonds, Clubs, Spades)
        uint8 rank;   // 2-14 (2-10, Jack=11, Queen=12, King=13, Ace=14)
    }

    struct HandResult {
        HandRank rank;
        uint256 score;    // Higher score wins within same rank
        Card[] bestHand;  // The 5 cards that make up the best hand
    }

    /**
     * @dev Evaluates a poker hand from the given cards
     * @param playerCards Array of player's hole cards
     * @param communityCards Array of community cards
     * @return HandResult containing the hand rank and score
     */
    function evaluateHand(Card[] memory playerCards, Card[] memory communityCards) 
        internal 
        pure 
        returns (HandResult memory) 
    {
        require(playerCards.length == 2, "Must have exactly 2 hole cards");
        require(communityCards.length <= 5, "Cannot have more than 5 community cards");

        // Combine player and community cards
        Card[] memory allCards = new Card[](playerCards.length + communityCards.length);
        uint256 cardCount = 0;
        
        for (uint256 i = 0; i < playerCards.length; i++) {
            allCards[cardCount] = playerCards[i];
            cardCount++;
        }
        
        for (uint256 i = 0; i < communityCards.length; i++) {
            allCards[cardCount] = communityCards[i];
            cardCount++;
        }

        // Sort cards by rank (bubble sort for simplicity)
        for (uint256 i = 0; i < cardCount - 1; i++) {
            for (uint256 j = 0; j < cardCount - i - 1; j++) {
                if (allCards[j].rank > allCards[j + 1].rank) {
                    Card memory temp = allCards[j];
                    allCards[j] = allCards[j + 1];
                    allCards[j + 1] = temp;
                }
            }
        }

        // Check for each hand rank from highest to lowest
        HandResult memory result;
        
        if (_isRoyalFlush(allCards)) {
            result.rank = HandRank.RoyalFlush;
            result.score = _calculateScore(allCards);
        }
        else if (_isStraightFlush(allCards)) {
            result.rank = HandRank.StraightFlush;
            result.score = _calculateScore(allCards);
        }
        else if (_isFourOfAKind(allCards)) {
            result.rank = HandRank.FourOfAKind;
            result.score = _calculateScore(allCards);
        }
        else if (_isFullHouse(allCards)) {
            result.rank = HandRank.FullHouse;
            result.score = _calculateScore(allCards);
        }
        else if (_isFlush(allCards)) {
            result.rank = HandRank.Flush;
            result.score = _calculateScore(allCards);
        }
        else if (_isStraight(allCards)) {
            result.rank = HandRank.Straight;
            result.score = _calculateScore(allCards);
        }
        else if (_isThreeOfAKind(allCards)) {
            result.rank = HandRank.ThreeOfAKind;
            result.score = _calculateScore(allCards);
        }
        else if (_isTwoPair(allCards)) {
            result.rank = HandRank.TwoPair;
            result.score = _calculateScore(allCards);
        }
        else if (_isPair(allCards)) {
            result.rank = HandRank.Pair;
            result.score = _calculateScore(allCards);
        }
        else {
            result.rank = HandRank.HighCard;
            result.score = _calculateScore(allCards);
        }

        result.bestHand = _getBestFiveCards(allCards, result.rank);
        return result;
    }

    /**
     * @dev Compares two hands and returns true if hand1 wins
     */
    function compareHands(HandResult memory hand1, HandResult memory hand2) 
        internal 
        pure 
        returns (bool) 
    {
        if (uint8(hand1.rank) > uint8(hand2.rank)) {
            return true;
        }
        else if (uint8(hand1.rank) < uint8(hand2.rank)) {
            return false;
        }
        else {
            return hand1.score > hand2.score;
        }
    }

    // Internal helper functions
    function _calculateScore(Card[] memory cards) private pure returns (uint256) {
        uint256 score = 0;
        for (uint256 i = 0; i < cards.length; i++) {
            score = score * 15 + cards[i].rank;  // Base 15 to handle Ace high
        }
        return score;
    }

    function _getBestFiveCards(Card[] memory cards, HandRank /* rank */) 
        private 
        pure 
        returns (Card[] memory) 
    {
        Card[] memory bestHand = new Card[](5);
        // Implementation would select the best 5 cards based on the hand rank
        // For now, just return the highest 5 cards
        uint256 count = 0;
        for (uint256 i = cards.length - 1; i >= 0 && count < 5; i--) {
            bestHand[count] = cards[i];
            count++;
        }
        return bestHand;
    }

    // Hand check functions
    function _isRoyalFlush(Card[] memory cards) private pure returns (bool) {
        // Check for Ace-high straight flush
        if (!_isStraightFlush(cards)) return false;
        
        // Find the highest straight flush
        uint8 suit = cards[0].suit;
        uint8[] memory ranks = new uint8[](cards.length);
        uint256 suitCount = 0;
        
        for (uint256 i = 0; i < cards.length; i++) {
            if (cards[i].suit == suit) {
                ranks[suitCount] = cards[i].rank;
                suitCount++;
            }
        }
        
        // Check if we have Ace, King, Queen, Jack, 10 in the same suit
        bool hasAce = false;
        bool hasKing = false;
        bool hasQueen = false;
        bool hasJack = false;
        bool hasTen = false;
        
        for (uint256 i = 0; i < suitCount; i++) {
            if (ranks[i] == 14) hasAce = true;
            if (ranks[i] == 13) hasKing = true;
            if (ranks[i] == 12) hasQueen = true;
            if (ranks[i] == 11) hasJack = true;
            if (ranks[i] == 10) hasTen = true;
        }
        
        return hasAce && hasKing && hasQueen && hasJack && hasTen;
    }

    function _isStraightFlush(Card[] memory cards) private pure returns (bool) {
        // Check each suit for a straight
        for (uint8 suit = 0; suit < 4; suit++) {
            uint8[] memory ranks = new uint8[](cards.length);
            uint256 suitCount = 0;
            
            // Get all cards of current suit
            for (uint256 i = 0; i < cards.length; i++) {
                if (cards[i].suit == suit) {
                    ranks[suitCount] = cards[i].rank;
                    suitCount++;
                }
            }
            
            // Need at least 5 cards of same suit for a straight flush
            if (suitCount >= 5) {
                // Sort ranks
                for (uint256 i = 0; i < suitCount - 1; i++) {
                    for (uint256 j = 0; j < suitCount - i - 1; j++) {
                        if (ranks[j] > ranks[j + 1]) {
                            uint8 temp = ranks[j];
                            ranks[j] = ranks[j + 1];
                            ranks[j + 1] = temp;
                        }
                    }
                }
                
                // Check for straight in these ranks
                uint256 consecutiveCount = 1;
                for (uint256 i = 1; i < suitCount; i++) {
                    if (ranks[i] == ranks[i-1] + 1) {
                        consecutiveCount++;
                        if (consecutiveCount >= 5) return true;
                    }
                    else if (ranks[i] != ranks[i-1]) {
                        consecutiveCount = 1;
                    }
                }
                
                // Check for Ace-low straight (A,2,3,4,5)
                if (ranks[suitCount-1] == 14) {  // If we have an Ace
                    bool hasTwo = false;
                    bool hasThree = false;
                    bool hasFour = false;
                    bool hasFive = false;
                    
                    for (uint256 i = 0; i < suitCount; i++) {
                        if (ranks[i] == 2) hasTwo = true;
                        if (ranks[i] == 3) hasThree = true;
                        if (ranks[i] == 4) hasFour = true;
                        if (ranks[i] == 5) hasFive = true;
                    }
                    
                    if (hasTwo && hasThree && hasFour && hasFive) return true;
                }
            }
        }
        return false;
    }

    function _isFourOfAKind(Card[] memory cards) private pure returns (bool) {
        // Count occurrences of each rank
        uint8[15] memory rankCount;  // Index 0-1 unused, 2-14 for card ranks
        
        for (uint256 i = 0; i < cards.length; i++) {
            rankCount[cards[i].rank]++;
            if (rankCount[cards[i].rank] == 4) return true;
        }
        
        return false;
    }

    function _isFullHouse(Card[] memory cards) private pure returns (bool) {
        // Count occurrences of each rank
        uint8[15] memory rankCount;  // Index 0-1 unused, 2-14 for card ranks
        bool hasThree = false;
        bool hasTwo = false;
        
        for (uint256 i = 0; i < cards.length; i++) {
            rankCount[cards[i].rank]++;
        }
        
        for (uint8 rank = 2; rank <= 14; rank++) {
            if (rankCount[rank] == 3) {
                if (hasTwo) return true;
                hasThree = true;
            }
            else if (rankCount[rank] == 2) {
                if (hasThree) return true;
                hasTwo = true;
            }
        }
        
        return false;
    }

    function _isFlush(Card[] memory cards) private pure returns (bool) {
        // Count cards of each suit
        uint8[4] memory suitCount;
        
        for (uint256 i = 0; i < cards.length; i++) {
            suitCount[cards[i].suit]++;
            if (suitCount[cards[i].suit] >= 5) return true;
        }
        
        return false;
    }

    function _isStraight(Card[] memory cards) private pure returns (bool) {
        // Get unique ranks
        bool[15] memory ranks;  // Index 0-1 unused, 2-14 for card ranks
        
        for (uint256 i = 0; i < cards.length; i++) {
            ranks[cards[i].rank] = true;
        }
        
        // Check for regular straight
        uint256 consecutiveCount = 0;
        for (uint8 rank = 2; rank <= 14; rank++) {
            if (ranks[rank]) {
                consecutiveCount++;
                if (consecutiveCount >= 5) return true;
            }
            else {
                consecutiveCount = 0;
            }
        }
        
        // Check for Ace-low straight (A,2,3,4,5)
        if (ranks[14] && ranks[2] && ranks[3] && ranks[4] && ranks[5]) {
            return true;
        }
        
        return false;
    }

    function _isThreeOfAKind(Card[] memory cards) private pure returns (bool) {
        // Count occurrences of each rank
        uint8[15] memory rankCount;  // Index 0-1 unused, 2-14 for card ranks
        
        for (uint256 i = 0; i < cards.length; i++) {
            rankCount[cards[i].rank]++;
            if (rankCount[cards[i].rank] == 3) return true;
        }
        
        return false;
    }

    function _isTwoPair(Card[] memory cards) private pure returns (bool) {
        // Count occurrences of each rank
        uint8[15] memory rankCount;  // Index 0-1 unused, 2-14 for card ranks
        uint256 pairCount = 0;
        
        for (uint256 i = 0; i < cards.length; i++) {
            rankCount[cards[i].rank]++;
            if (rankCount[cards[i].rank] == 2) {
                pairCount++;
                if (pairCount >= 2) return true;
            }
        }
        
        return false;
    }

    function _isPair(Card[] memory cards) private pure returns (bool) {
        // Count occurrences of each rank
        uint8[15] memory rankCount;  // Index 0-1 unused, 2-14 for card ranks
        
        for (uint256 i = 0; i < cards.length; i++) {
            rankCount[cards[i].rank]++;
            if (rankCount[cards[i].rank] == 2) return true;
        }
        
        return false;
    }
} 