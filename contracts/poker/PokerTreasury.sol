// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IPokerTable.sol";
import "../HouseTreasury.sol";

/**
 * @title PokerTreasury
 * @dev Contract for managing poker treasury interactions
 */
contract PokerTreasury is Ownable {
    IPokerTable public pokerTable;
    HouseTreasury public treasury;

    // Events
    event RakeCollected(uint256 indexed tableId, uint256 amount);
    event RakeDistributed(uint256 indexed tableId, uint256 amount);
    event EmergencyWithdrawal(uint256 amount);

    // Error messages
    error InvalidAmount();
    error TransferFailed();
    error NotAuthorized();
    error InsufficientBalance();

    // Constants
    uint256 public constant RAKE_PERCENTAGE = 25; // 2.5%
    uint256 public constant RAKE_DENOMINATOR = 1000;
    uint256 public constant MAX_RAKE = 0.1 ether; // Maximum rake per hand

    constructor(address _pokerTableAddress, address payable _treasuryAddress) Ownable(msg.sender) {
        pokerTable = IPokerTable(_pokerTableAddress);
        treasury = HouseTreasury(_treasuryAddress);
    }

    /**
     * @dev Updates the PokerTable contract address
     */
    function setPokerTable(address _pokerTableAddress) external onlyOwner {
        require(_pokerTableAddress != address(0), "Invalid address");
        pokerTable = IPokerTable(_pokerTableAddress);
    }

    /**
     * @dev Collects rake from a pot
     */
    function collectRake(uint256 tableId, uint256 potAmount) external returns (uint256) {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();

        // Calculate rake amount
        uint256 rakeAmount = (potAmount * RAKE_PERCENTAGE) / RAKE_DENOMINATOR;
        if (rakeAmount > MAX_RAKE) {
            rakeAmount = MAX_RAKE;
        }

        emit RakeCollected(tableId, rakeAmount);
        return rakeAmount;
    }

    /**
     * @dev Distributes collected rake to the house treasury
     */
    function distributeRake(uint256 tableId, uint256 amount) external {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();
        if (amount == 0) revert InvalidAmount();

        // Transfer rake to treasury
        (bool success,) = address(treasury).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit RakeDistributed(tableId, amount);
    }

    /**
     * @dev Emergency withdrawal of funds to treasury
     * Only callable by owner
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();

        // Transfer all funds to treasury
        (bool success,) = address(treasury).call{value: balance}("");
        if (!success) revert TransferFailed();

        emit EmergencyWithdrawal(balance);
    }

    /**
     * @dev Returns the current balance of the contract
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Allows the contract to receive ETH
     */
    receive() external payable {}

    /**
     * @dev Fallback function
     */
    fallback() external payable {}
} 