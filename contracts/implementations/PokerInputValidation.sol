// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title PokerInputValidation
 * @dev Implements comprehensive input validation for the poker game
 * Security features:
 * 1. Input validation for all game parameters
 * 2. Safe math operations
 * 3. Boundary checks
 */
contract PokerInputValidation is ReentrancyGuard {
    using SafeMath for uint256;

    // Constants for validation
    uint256 public constant MIN_BUY_IN = 0.01 ether;
    uint256 public constant MAX_BUY_IN = 100 ether;
    uint256 public constant MIN_BLIND = 0.001 ether;
    uint256 public constant MAX_BLIND = 1 ether;
    uint8 public constant MIN_PLAYERS = 2;
    uint8 public constant MAX_PLAYERS = 6;
    uint8 public constant MAX_TABLES = 10;
    uint8 public constant MAX_ROUNDS = 4; // PreFlop, Flop, Turn, River

    // Events for validation failures
    event ValidationFailed(string reason, uint256 value);
    event BoundaryCheckFailed(string parameter, uint256 value, uint256 min, uint256 max);

    // Modifiers for common validations
    modifier validateAddress(address addr) {
        require(addr != address(0), "Invalid address");
        require(addr != address(this), "Cannot be contract address");
        _;
    }

    modifier validateTableId(uint256 tableId) {
        require(tableId < MAX_TABLES, "Invalid table ID");
        _;
    }

    modifier validatePlayerCount(uint8 count) {
        require(count >= MIN_PLAYERS && count <= MAX_PLAYERS, "Invalid player count");
        _;
    }

    // Buy-in validation
    function validateBuyIn(uint256 amount, uint256 minBuyIn, uint256 maxBuyIn) public pure returns (bool) {
        require(amount >= MIN_BUY_IN && amount <= MAX_BUY_IN, "Buy-in outside global limits");
        require(amount >= minBuyIn && amount <= maxBuyIn, "Buy-in outside table limits");
        require(amount > 0 && amount % (0.001 ether) == 0, "Invalid buy-in amount");
        return true;
    }

    // Blind validation
    function validateBlinds(uint256 smallBlind, uint256 bigBlind) public pure returns (bool) {
        require(smallBlind >= MIN_BLIND && smallBlind <= MAX_BLIND, "Invalid small blind");
        require(bigBlind >= MIN_BLIND && bigBlind <= MAX_BLIND, "Invalid big blind");
        require(bigBlind == smallBlind.mul(2), "Big blind must be 2x small blind");
        return true;
    }

    // Bet validation
    function validateBet(
        uint256 amount,
        uint256 minBet,
        uint256 maxBet,
        uint256 playerBalance
    ) public pure returns (bool) {
        require(amount >= minBet && amount <= maxBet, "Bet outside limits");
        require(amount <= playerBalance, "Insufficient balance");
        require(amount > 0 && amount % (0.001 ether) == 0, "Invalid bet amount");
        return true;
    }

    // Position validation
    function validatePosition(uint8 position, uint8 playerCount) public pure returns (bool) {
        require(position < playerCount, "Invalid position");
        return true;
    }

    // Card validation
    function validateCard(uint8 card) public pure returns (bool) {
        require(card > 0 && card <= 52, "Invalid card value");
        return true;
    }

    function validatePlayerCards(uint8[] memory cards) public pure returns (bool) {
        require(cards.length == 2, "Invalid player card count");
        for (uint8 i = 0; i < cards.length; i++) {
            require(validateCard(cards[i]), "Invalid player card");
            // Check for duplicates
            for (uint8 j = i + 1; j < cards.length; j++) {
                require(cards[i] != cards[j], "Duplicate cards not allowed");
            }
        }
        return true;
    }

    function validateCommunityCards(uint8[] memory cards) public pure returns (bool) {
        require(cards.length <= 5, "Too many community cards");
        for (uint8 i = 0; i < cards.length; i++) {
            require(validateCard(cards[i]), "Invalid community card");
            // Check for duplicates
            for (uint8 j = i + 1; j < cards.length; j++) {
                require(cards[i] != cards[j], "Duplicate cards not allowed");
            }
        }
        return true;
    }

    // Game state validation
    function validateGameState(uint8 currentState, uint8 newState) public pure returns (bool) {
        require(newState <= MAX_ROUNDS, "Invalid game state");
        require(newState > currentState, "Invalid state transition");
        return true;
    }

    // Safe math operations
    function safeAdd(uint256 a, uint256 b) public pure returns (uint256) {
        return a.add(b);
    }

    function safeSub(uint256 a, uint256 b) public pure returns (uint256) {
        return a.sub(b);
    }

    function safeMul(uint256 a, uint256 b) public pure returns (uint256) {
        return a.mul(b);
    }

    function safeDiv(uint256 a, uint256 b) public pure returns (uint256) {
        return a.div(b);
    }

    // Boundary checks
    function checkBoundary(
        uint256 value,
        uint256 minValue,
        uint256 maxValue,
        string memory parameter
    ) public returns (bool) {
        if (value < minValue || value > maxValue) {
            emit BoundaryCheckFailed(parameter, value, minValue, maxValue);
            return false;
        }
        return true;
    }

    // Utility functions
    function isValidAmount(uint256 amount) public pure returns (bool) {
        return amount > 0 && amount <= MAX_BUY_IN;
    }

    function isValidBlind(uint256 blind) public pure returns (bool) {
        return blind >= MIN_BLIND && blind <= MAX_BLIND;
    }

    function isValidPlayerCount(uint8 count) public pure returns (bool) {
        return count >= MIN_PLAYERS && count <= MAX_PLAYERS;
    }
} 