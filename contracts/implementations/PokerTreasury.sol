// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./PokerAccessControl.sol";

/**
 * @title PokerTreasury
 * @dev Implements secure treasury management for the poker game
 * Security features:
 * 1. Secure fund management
 * 2. Withdrawal limits and delays
 * 3. Multi-signature functionality
 */
contract PokerTreasury is ReentrancyGuard, Pausable, PokerAccessControl {
    using SafeMath for uint256;

    // Constants
    uint256 public constant MAX_DAILY_WITHDRAWAL = 100 ether;
    uint256 public constant WITHDRAWAL_DELAY = 24 hours;
    uint256 public constant LARGE_TRANSACTION_THRESHOLD = 10 ether;
    uint8 public constant REQUIRED_SIGNATURES = 2;

    // Structures
    struct WithdrawalRequest {
        address requester;
        uint256 amount;
        uint256 requestTime;
        bool executed;
        mapping(address => bool) signatures;
        uint8 signatureCount;
    }

    struct DailyLimit {
        uint256 amount;
        uint256 resetTime;
        uint256 spentToday;
    }

    // State variables
    mapping(address => uint256) public balances;
    mapping(address => DailyLimit) public dailyLimits;
    mapping(address => uint256) public lastWithdrawalTime;
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
    uint256 public withdrawalRequestCount;
    uint256 public totalFunds;
    uint256 public houseFeePercent; // in basis points (1/100 of a percent)

    // Events
    event FundsDeposited(address indexed player, uint256 amount);
    event WithdrawalRequested(uint256 indexed requestId, address indexed player, uint256 amount);
    event WithdrawalApproved(uint256 indexed requestId, address indexed approver);
    event WithdrawalExecuted(uint256 indexed requestId, address indexed player, uint256 amount);
    event DailyLimitUpdated(address indexed player, uint256 newLimit);
    event HouseFeeUpdated(uint256 newFeePercent);
    event EmergencyWithdrawal(address indexed player, uint256 amount);

    constructor() {
        withdrawalRequestCount = 0;
        houseFeePercent = 250; // 2.5% default house fee
    }

    // Fund management
    function deposit() external payable nonReentrant {
        require(msg.value > 0, "Invalid deposit amount");
        balances[msg.sender] = balances[msg.sender].add(msg.value);
        totalFunds = totalFunds.add(msg.value);
        emit FundsDeposited(msg.sender, msg.value);
    }

    function requestWithdrawal(uint256 amount) external nonReentrant returns (uint256) {
        require(amount > 0, "Invalid withdrawal amount");
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(
            amount <= getDailyLimitRemaining(msg.sender),
            "Exceeds daily withdrawal limit"
        );

        uint256 requestId = withdrawalRequestCount++;
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        request.requester = msg.sender;
        request.amount = amount;
        request.requestTime = block.timestamp;
        request.executed = false;
        request.signatureCount = 0;

        // Auto-approve small withdrawals
        if (amount < LARGE_TRANSACTION_THRESHOLD) {
            executeWithdrawal(requestId);
        } else {
            emit WithdrawalRequested(requestId, msg.sender, amount);
        }

        return requestId;
    }

    function approveWithdrawal(uint256 requestId) external onlyTreasuryManager {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        require(!request.executed, "Withdrawal already executed");
        require(!request.signatures[msg.sender], "Already signed");
        require(
            block.timestamp >= request.requestTime + WITHDRAWAL_DELAY,
            "Withdrawal delay not met"
        );

        request.signatures[msg.sender] = true;
        request.signatureCount++;

        emit WithdrawalApproved(requestId, msg.sender);

        if (request.signatureCount >= REQUIRED_SIGNATURES) {
            executeWithdrawal(requestId);
        }
    }

    function executeWithdrawal(uint256 requestId) internal {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        require(!request.executed, "Withdrawal already executed");
        require(balances[request.requester] >= request.amount, "Insufficient balance");

        request.executed = true;
        balances[request.requester] = balances[request.requester].sub(request.amount);
        totalFunds = totalFunds.sub(request.amount);
        
        // Update daily limit
        DailyLimit storage limit = dailyLimits[request.requester];
        if (block.timestamp > limit.resetTime) {
            limit.spentToday = request.amount;
            limit.resetTime = block.timestamp + 1 days;
        } else {
            limit.spentToday = limit.spentToday.add(request.amount);
        }

        lastWithdrawalTime[request.requester] = block.timestamp;
        payable(request.requester).transfer(request.amount);
        
        emit WithdrawalExecuted(requestId, request.requester, request.amount);
    }

    // House fee management
    function collectHouseFee(uint256 amount) internal returns (uint256) {
        uint256 fee = amount.mul(houseFeePercent).div(10000);
        totalFunds = totalFunds.add(fee);
        return fee;
    }

    function updateHouseFee(uint256 newFeePercent) external onlyGameAdmin {
        require(newFeePercent <= 1000, "Fee too high"); // Max 10%
        houseFeePercent = newFeePercent;
        emit HouseFeeUpdated(newFeePercent);
    }

    // Daily limit management
    function setDailyLimit(address player, uint256 limit) external onlyGameAdmin {
        require(limit <= MAX_DAILY_WITHDRAWAL, "Limit too high");
        dailyLimits[player].amount = limit;
        dailyLimits[player].resetTime = block.timestamp + 1 days;
        dailyLimits[player].spentToday = 0;
        emit DailyLimitUpdated(player, limit);
    }

    function getDailyLimitRemaining(address player) public view returns (uint256) {
        DailyLimit storage limit = dailyLimits[player];
        if (block.timestamp > limit.resetTime) {
            return limit.amount;
        }
        if (limit.spentToday >= limit.amount) {
            return 0;
        }
        return limit.amount.sub(limit.spentToday);
    }

    // Emergency functions
    function emergencyWithdraw(address player) external onlyEmergencyAdmin whenPaused {
        uint256 amount = balances[player];
        require(amount > 0, "No balance to withdraw");
        require(
            block.timestamp >= lastWithdrawalTime[player] + WITHDRAWAL_DELAY,
            "Withdrawal delay not met"
        );

        balances[player] = 0;
        totalFunds = totalFunds.sub(amount);
        payable(player).transfer(amount);

        emit EmergencyWithdrawal(player, amount);
    }

    // View functions
    function getBalance(address player) external view returns (uint256) {
        return balances[player];
    }

    function getWithdrawalRequest(uint256 requestId) external view returns (
        address requester,
        uint256 amount,
        uint256 requestTime,
        bool executed,
        uint8 signatureCount
    ) {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        return (
            request.requester,
            request.amount,
            request.requestTime,
            request.executed,
            request.signatureCount
        );
    }

    // Receive function
    receive() external payable {
        deposit();
    }
} 