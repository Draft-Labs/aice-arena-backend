// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PokerEvents.sol";

contract PokerHandEval is PokerEvents {

    // Evaluate a poker hand and return its rank and score
    function evaluateHand(uint8[] memory cards) public pure returns (HandRank, uint256) {
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
}
