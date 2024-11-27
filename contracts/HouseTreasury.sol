// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract HouseTreasury is ReentrancyGuard {
    address public owner;
    mapping(address => bool) public authorizedGames;
    bool private paused;

    event GameAuthorized(address gameContract);
    event GameDeauthorized(address gameContract);
    event TreasuryFunded(uint256 amount);
    event ContractPaused();
    event ContractUnpaused();

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    modifier onlyAuthorizedGame() {
        require(authorizedGames[msg.sender], "Only authorized games can call this function.");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    function authorizeGame(address gameContract) external onlyOwner whenNotPaused {
        authorizedGames[gameContract] = true;
        emit GameAuthorized(gameContract);
    }

    function deauthorizeGame(address gameContract) external onlyOwner whenNotPaused {
        authorizedGames[gameContract] = false;
        emit GameDeauthorized(gameContract);
    }

    function fundTreasury() external payable onlyOwner whenNotPaused {
        require(msg.value > 0, "Must send some Ether to fund the treasury.");
        emit TreasuryFunded(msg.value);
    }

    function getTreasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function payout(address winner, uint256 amount) external onlyAuthorizedGame nonReentrant whenNotPaused {
        require(amount <= address(this).balance, "Not enough balance in treasury to payout.");
        
        (bool success, ) = winner.call{value: amount}("");
        require(success, "Transfer failed.");
    }

    function pause() external onlyOwner {
        paused = true;
        emit ContractPaused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit ContractUnpaused();
    }

    // Fallback function to handle unexpected Ether transfers
    receive() external payable {
        emit TreasuryFunded(msg.value);
    }
}