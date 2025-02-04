// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./PokerAccessControl.sol";

/**
 * @title PokerGameSecurity
 * @dev Implements game logic security features for the poker game
 * Security features:
 * 1. Game state validations
 * 2. Timeouts and deadlines
 * 3. Dispute resolution mechanism
 */
contract PokerGameSecurity is ReentrancyGuard, PokerAccessControl {
    using SafeMath for uint256;

    // Constants for timeouts and limits
    uint256 public constant PLAYER_TURN_TIMEOUT = 5 minutes;
    uint256 public constant DISPUTE_WINDOW = 1 days;
    uint256 public constant MAX_DISPUTE_STAKE = 1 ether;
    uint256 public constant MIN_DISPUTE_STAKE = 0.1 ether;
    uint8 public constant MAX_DISPUTES_PER_PLAYER = 3;

    // Structures
    struct GameTimer {
        uint256 lastActionTime;
        uint256 turnStartTime;
        uint256 roundStartTime;
        bool isActive;
    }

    struct Dispute {
        address initiator;
        address defendant;
        uint256 tableId;
        uint256 roundNumber;
        uint256 stake;
        string reason;
        bool resolved;
        bool valid;
        uint256 timeCreated;
    }

    // State variables
    mapping(uint256 => GameTimer) public gameTimers;                  // tableId => GameTimer
    mapping(uint256 => mapping(address => uint256)) public lastActionTimes;  // tableId => player => lastActionTime
    mapping(address => uint8) public playerDisputeCount;              // player => number of disputes initiated
    mapping(uint256 => Dispute) public disputes;                      // disputeId => Dispute
    uint256 public disputeCount;

    // Events
    event GameTimeout(uint256 indexed tableId, address indexed player);
    event DisputeCreated(uint256 indexed disputeId, uint256 indexed tableId, address indexed initiator);
    event DisputeResolved(uint256 indexed disputeId, bool valid);
    event PlayerPenalized(address indexed player, string reason);
    event StateValidationFailed(uint256 indexed tableId, string reason);
    event TimeoutWarning(uint256 indexed tableId, address indexed player, uint256 remainingTime);

    constructor() {
        disputeCount = 0;
    }

    // Game state validation
    function validateGameState(
        uint256 tableId,
        uint8 currentState,
        uint8 newState,
        uint8 playerCount,
        uint256 pot
    ) public returns (bool) {
        require(currentState < newState, "Invalid state transition");
        require(playerCount >= MIN_PLAYERS, "Not enough players");
        require(pot >= 0, "Invalid pot amount");

        // Validate specific state transitions
        if (newState == uint8(GameState.PreFlop)) {
            require(playerCount >= 2, "Need at least 2 players for PreFlop");
        } else if (newState == uint8(GameState.Showdown)) {
            require(pot > 0, "Pot must be greater than 0 for Showdown");
        }

        // Update game timer
        gameTimers[tableId].roundStartTime = block.timestamp;
        gameTimers[tableId].isActive = true;

        return true;
    }

    // Timeout management
    function updatePlayerTimer(uint256 tableId, address player) public {
        lastActionTimes[tableId][player] = block.timestamp;
        gameTimers[tableId].lastActionTime = block.timestamp;
    }

    function checkTimeout(uint256 tableId, address player) public view returns (bool) {
        if (!gameTimers[tableId].isActive) return false;
        return block.timestamp > lastActionTimes[tableId][player] + PLAYER_TURN_TIMEOUT;
    }

    function enforceTimeout(uint256 tableId, address player) public {
        require(checkTimeout(tableId, player), "No timeout occurred");
        emit GameTimeout(tableId, player);
        // Additional timeout handling logic to be implemented in game contract
    }

    // Dispute resolution
    function createDispute(
        uint256 tableId,
        address defendant,
        string memory reason
    ) external payable returns (uint256) {
        require(msg.value >= MIN_DISPUTE_STAKE, "Insufficient dispute stake");
        require(msg.value <= MAX_DISPUTE_STAKE, "Excessive dispute stake");
        require(playerDisputeCount[msg.sender] < MAX_DISPUTES_PER_PLAYER, "Too many disputes");
        require(block.timestamp <= gameTimers[tableId].roundStartTime + DISPUTE_WINDOW, "Dispute window closed");

        uint256 disputeId = disputeCount++;
        disputes[disputeId] = Dispute({
            initiator: msg.sender,
            defendant: defendant,
            tableId: tableId,
            roundNumber: getCurrentRound(tableId),
            stake: msg.value,
            reason: reason,
            resolved: false,
            valid: false,
            timeCreated: block.timestamp
        });

        playerDisputeCount[msg.sender]++;
        emit DisputeCreated(disputeId, tableId, msg.sender);
        return disputeId;
    }

    function resolveDispute(uint256 disputeId, bool valid) external onlyGameAdmin {
        Dispute storage dispute = disputes[disputeId];
        require(!dispute.resolved, "Dispute already resolved");
        require(block.timestamp <= dispute.timeCreated + DISPUTE_WINDOW, "Resolution window closed");

        dispute.resolved = true;
        dispute.valid = valid;

        // Return stake to initiator if dispute is valid
        if (valid) {
            payable(dispute.initiator).transfer(dispute.stake);
            emit PlayerPenalized(dispute.defendant, dispute.reason);
        } else {
            // Transfer stake to treasury if dispute is invalid
            payable(owner()).transfer(dispute.stake);
        }

        emit DisputeResolved(disputeId, valid);
    }

    // Helper functions
    function getCurrentRound(uint256 tableId) internal view returns (uint256) {
        return gameTimers[tableId].roundStartTime;
    }

    function isWithinTurnTime(uint256 tableId, address player) public view returns (bool) {
        return block.timestamp <= lastActionTimes[tableId][player] + PLAYER_TURN_TIMEOUT;
    }

    function getRemainingTurnTime(uint256 tableId, address player) public view returns (uint256) {
        uint256 deadline = lastActionTimes[tableId][player] + PLAYER_TURN_TIMEOUT;
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    // Warning system
    function checkAndEmitTimeoutWarning(uint256 tableId, address player) public {
        uint256 remainingTime = getRemainingTurnTime(tableId, player);
        if (remainingTime <= 30) { // 30 seconds warning
            emit TimeoutWarning(tableId, player, remainingTime);
        }
    }

    // Penalty system
    function penalizePlayer(address player, string memory reason) public onlyGameAdmin {
        emit PlayerPenalized(player, reason);
        // Additional penalty logic to be implemented in game contract
    }
} 