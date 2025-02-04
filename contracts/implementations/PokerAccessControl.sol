// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title PokerAccessControl
 * @dev Implements role-based access control and emergency functionality for the poker game
 * Security features:
 * 1. Role-based access control
 * 2. Emergency pause functionality
 * 3. Enhanced modifier security
 */
contract PokerAccessControl is AccessControl, Pausable, ReentrancyGuard {
    // Role definitions
    bytes32 public constant GAME_ADMIN = keccak256("GAME_ADMIN");
    bytes32 public constant DEALER = keccak256("DEALER");
    bytes32 public constant TREASURY_MANAGER = keccak256("TREASURY_MANAGER");
    bytes32 public constant EMERGENCY_ADMIN = keccak256("EMERGENCY_ADMIN");

    // Events
    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);
    event EmergencyPaused(address indexed admin);
    event EmergencyUnpaused(address indexed admin);
    event SecurityLimitUpdated(string indexed limitType, uint256 newValue);

    // Security limits
    uint256 public maxBetLimit;
    uint256 public maxTableLimit;
    uint256 public maxPlayerLimit;
    uint256 public emergencyWithdrawalDelay;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(GAME_ADMIN, msg.sender);
        _grantRole(EMERGENCY_ADMIN, msg.sender);
        
        // Set initial security limits
        maxBetLimit = 100 ether;
        maxTableLimit = 10;
        maxPlayerLimit = 6;
        emergencyWithdrawalDelay = 24 hours;
    }

    // Access control modifiers
    modifier onlyGameAdmin() {
        require(hasRole(GAME_ADMIN, msg.sender), "Caller is not a game admin");
        _;
    }

    modifier onlyDealer() {
        require(hasRole(DEALER, msg.sender), "Caller is not a dealer");
        _;
    }

    modifier onlyTreasuryManager() {
        require(hasRole(TREASURY_MANAGER, msg.sender), "Caller is not a treasury manager");
        _;
    }

    modifier onlyEmergencyAdmin() {
        require(hasRole(EMERGENCY_ADMIN, msg.sender), "Caller is not an emergency admin");
        _;
    }

    // Emergency functions
    function pauseGame() external onlyEmergencyAdmin {
        _pause();
        emit EmergencyPaused(msg.sender);
    }

    function unpauseGame() external onlyEmergencyAdmin {
        _unpause();
        emit EmergencyUnpaused(msg.sender);
    }

    // Security limit management
    function updateMaxBetLimit(uint256 newLimit) external onlyGameAdmin {
        require(newLimit > 0, "Invalid bet limit");
        maxBetLimit = newLimit;
        emit SecurityLimitUpdated("MaxBet", newLimit);
    }

    function updateMaxTableLimit(uint256 newLimit) external onlyGameAdmin {
        require(newLimit > 0, "Invalid table limit");
        maxTableLimit = newLimit;
        emit SecurityLimitUpdated("MaxTable", newLimit);
    }

    function updateMaxPlayerLimit(uint256 newLimit) external onlyGameAdmin {
        require(newLimit > 0 && newLimit <= 10, "Invalid player limit");
        maxPlayerLimit = newLimit;
        emit SecurityLimitUpdated("MaxPlayer", newLimit);
    }

    function updateEmergencyWithdrawalDelay(uint256 newDelay) external onlyEmergencyAdmin {
        require(newDelay >= 1 hours, "Delay too short");
        emergencyWithdrawalDelay = newDelay;
        emit SecurityLimitUpdated("WithdrawalDelay", newDelay);
    }

    // Role management
    function addGameAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(GAME_ADMIN, account);
    }

    function removeGameAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(GAME_ADMIN, account);
    }

    function addDealer(address account) external onlyGameAdmin {
        grantRole(DEALER, account);
    }

    function removeDealer(address account) external onlyGameAdmin {
        revokeRole(DEALER, account);
    }

    function addTreasuryManager(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(TREASURY_MANAGER, account);
    }

    function removeTreasuryManager(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(TREASURY_MANAGER, account);
    }

    function addEmergencyAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(EMERGENCY_ADMIN, account);
    }

    function removeEmergencyAdmin(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(EMERGENCY_ADMIN, account);
    }

    // Security checks
    function validateBetAmount(uint256 amount) public view {
        require(amount <= maxBetLimit, "Bet exceeds maximum limit");
        require(amount > 0, "Bet amount must be positive");
    }

    function validateTableCount(uint256 currentCount) public view {
        require(currentCount < maxTableLimit, "Maximum table limit reached");
    }

    function validatePlayerCount(uint256 currentCount) public view {
        require(currentCount < maxPlayerLimit, "Maximum player limit reached");
    }

    // Emergency withdrawal validation
    function validateEmergencyWithdrawal(uint256 lastActionTime) public view {
        require(
            block.timestamp >= lastActionTime + emergencyWithdrawalDelay,
            "Emergency withdrawal delay not met"
        );
    }
} 