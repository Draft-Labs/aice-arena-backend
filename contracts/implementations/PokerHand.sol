// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPokerHand.sol";
import "./PokerBase.sol";

contract PokerHand is IPokerHand, PokerBase {
    constructor(address storageAddress) PokerBase(storageAddress) {}

    // Card validation
    function isValidCard(uint8 card) public pure returns (bool) {
        return card > 0 && card <= 52;
    }

    function isValidHand(uint8[] calldata cards) public pure returns (bool) {
        if (cards.length != 5 && cards.length != 7) return false;
        
        for (uint i = 0; i < cards.length; i++) {
            if (!isValidCard(cards[i])) return false;
            // Check for duplicates
            for (uint j = i + 1; j < cards.length; j++) {
                if (cards[i] == cards[j]) return false;
            }
        }
        return true;
    }

    function getCardRank(uint8 card) public pure returns (uint8) {
        return ((card - 1) % 13) + 1;
    }

    function getCardSuit(uint8 card) public pure returns (uint8) {
        return (card - 1) / 13;
    }

    // Card management
    function dealPlayerCards(uint256 tableId, address player, uint8[] memory cards) external onlyOwner {
        require(cards.length == 2, "Must deal exactly 2 cards");
        storage_.setPlayerCards(tableId, player, cards);
        
        // Emit optimized cards dealt event
        emit CardsDealt(
            tableId,
            player,
            0, // 0 = Player cards
            cards
        );
    }

    function dealCommunityCards(uint256 tableId, uint8[] memory cards) external onlyOwner {
        uint8[] memory existingCards = storage_.getCommunityCards(tableId);
        uint8 totalCards = uint8(existingCards.length + cards.length);
        require(totalCards <= 5, "Cannot deal more than 5 community cards");
        
        storage_.setCommunityCards(tableId, cards);
        
        // Emit optimized cards dealt event
        emit CardsDealt(
            tableId,
            address(0), // No specific player for community cards
            1, // 1 = Community cards
            cards
        );
    }

    function getPlayerCards(uint256 tableId, address player) external view returns (uint8[] memory) {
        require(msg.sender == player || msg.sender == owner(), "Not authorized");
        return storage_.getPlayer(tableId, player).holeCards;
    }

    function getCommunityCards(uint256 tableId) external view returns (uint8[] memory) {
        return storage_.getTableConfig(tableId).communityCards;
    }

    // Hand evaluation
    function evaluateHand(uint8[] calldata cards) public pure returns (HandRank rank, uint256 score) {
        require(isValidHand(cards), "Invalid hand");
        
        // Convert card numbers to values and suits
        uint8[] memory values = new uint8[](cards.length);
        uint8[] memory suits = new uint8[](cards.length);
        
        for (uint i = 0; i < cards.length; i++) {
            values[i] = getCardRank(cards[i]);
            suits[i] = getCardSuit(cards[i]);
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
                if (!(i == 0 && values[0] == 14 && values[1] == 5)) {
                    isStraight = false;
                    break;
                }
            }
        }

        // Count frequencies
        uint8[14] memory freq;
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
            if (i == 1) break;
        }

        // Calculate base score
        score = uint256(values[0]) * 100 + uint256(values[1]) * 10 + uint256(values[2]);

        // Determine hand rank
        if (isFlush && isStraight && values[0] == 14 && values[1] == 13) {
            return (HandRank.RoyalFlush, score);
        }
        if (isFlush && isStraight) {
            return (HandRank.StraightFlush, score);
        }
        if (maxFreq == 4) {
            return (HandRank.FourOfAKind, uint256(highestValue) * 100 + score);
        }
        if (maxFreq == 3 && secondMaxFreq == 2) {
            return (HandRank.FullHouse, uint256(highestValue) * 100 + uint256(secondHighestValue));
        }
        if (isFlush) {
            return (HandRank.Flush, score);
        }
        if (isStraight) {
            return (HandRank.Straight, score);
        }
        if (maxFreq == 3) {
            return (HandRank.ThreeOfAKind, uint256(highestValue) * 100 + score);
        }
        if (maxFreq == 2 && secondMaxFreq == 2) {
            return (HandRank.TwoPair, uint256(highestValue) * 100 + uint256(secondHighestValue) * 10 + uint256(values[4]));
        }
        if (maxFreq == 2) {
            return (HandRank.Pair, uint256(highestValue) * 100 + score);
        }
        return (HandRank.HighCard, score);
    }

    function compareHands(uint8[] calldata hand1, uint8[] calldata hand2) external pure returns (int8) {
        (HandRank rank1, uint256 score1) = evaluateHand(hand1);
        (HandRank rank2, uint256 score2) = evaluateHand(hand2);

        if (uint8(rank1) > uint8(rank2)) return 1;
        if (uint8(rank1) < uint8(rank2)) return -1;
        if (score1 > score2) return 1;
        if (score1 < score2) return -1;
        return 0;
    }

    function determineWinner(uint256 tableId) external returns (address winner, HandRank winningRank, uint256 winningScore) {
        address[] memory activePlayers = storage_.getTablePlayers(tableId);
        require(activePlayers.length >= 2, "Not enough players");

        winner = address(0);
        winningRank = HandRank.HighCard;
        winningScore = 0;

        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        uint8[] memory communityCards = config.communityCards;
        require(communityCards.length == 5, "Invalid community cards");

        for (uint i = 0; i < activePlayers.length; i++) {
            address playerAddr = activePlayers[i];
            PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, playerAddr);
            if (!player.isActive) continue;

            uint8[] memory playerCards = player.holeCards;
            require(playerCards.length == 2, "Invalid player cards");

            // Combine player and community cards
            uint8[] memory allCards = new uint8[](7);
            allCards[0] = playerCards[0];
            allCards[1] = playerCards[1];
            for (uint j = 0; j < 5; j++) {
                allCards[j + 2] = communityCards[j];
            }

            (HandRank rank, uint256 score) = evaluateHand(allCards);

            if (winner == address(0) ||
                uint8(rank) > uint8(winningRank) ||
                (uint8(rank) == uint8(winningRank) && score > winningScore)) {
                winner = playerAddr;
                winningRank = rank;
                winningScore = score;
            }
        }

        require(winner != address(0), "No winner found");
        return (winner, winningRank, winningScore);
    }
} 