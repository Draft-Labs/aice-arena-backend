// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract HouseTreasury is ReentrancyGuard {
    address public owner;
    mapping(address => bool) public authorizedGames;
    mapping(address => uint256) public playerBalances;
    mapping(address => bool) public activeAccounts;
    bool private paused;

    event GameAuthorized(address gameContract);
    event GameDeauthorized(address gameContract);
    event TreasuryFunded(uint256 amount);
    event AccountOpened(address indexed player, uint256 amount);
    event AccountClosed(address indexed player, uint256 amount);
    event BalanceUpdated(address indexed player, uint256 newBalance);
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

    modifier hasActiveAccount() {
        require(activeAccounts[msg.sender], "No active account");
        _;
    }

    // Players open an account by depositing ETH
    function openAccount() external payable whenNotPaused {
        require(msg.value > 0, "Must deposit ETH to open account");
        require(!activeAccounts[msg.sender], "Account already active");

        playerBalances[msg.sender] = msg.value;
        activeAccounts[msg.sender] = true;
        emit AccountOpened(msg.sender, msg.value);
    }

    // Players can deposit more ETH to their account
    function deposit() external payable whenNotPaused hasActiveAccount {
        require(msg.value > 0, "Must deposit some ETH");
        playerBalances[msg.sender] += msg.value;
        emit BalanceUpdated(msg.sender, playerBalances[msg.sender]);
    }

    // Players close their account and withdraw all funds
    function closeAccount() external nonReentrant hasActiveAccount {
        uint256 balance = playerBalances[msg.sender];
        require(balance > 0, "No balance to withdraw");

        playerBalances[msg.sender] = 0;
        activeAccounts[msg.sender] = false;
        
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed");
        
        emit AccountClosed(msg.sender, balance);
    }

    // Called by games to verify if a player can place a bet
    function canPlaceBet(address player, uint256 amount) external view 
        onlyAuthorizedGame returns (bool) {
        return activeAccounts[player] && playerBalances[player] >= amount;
    }

    // Called by games when a player loses a bet
    function processBetLoss(address player, uint256 amount) external 
        onlyAuthorizedGame {
        require(playerBalances[player] >= amount, "Insufficient balance");
        playerBalances[player] -= amount;
        emit BalanceUpdated(player, playerBalances[player]);
    }

    // Called by games when a player wins a bet
    function processBetWin(address player, uint256 amount) external 
        onlyAuthorizedGame {
        playerBalances[player] += amount;
        emit BalanceUpdated(player, playerBalances[player]);
    }

    function getPlayerBalance(address player) external view returns (uint256) {
        return playerBalances[player];
    }

    function authorizeGame(address gameContract) external onlyOwner {
        authorizedGames[gameContract] = true;
        emit GameAuthorized(gameContract);
    }

    function deauthorizeGame(address gameContract) external onlyOwner {
        authorizedGames[gameContract] = false;
        emit GameDeauthorized(gameContract);
    }

    function pause() external onlyOwner {
        paused = true;
        emit ContractPaused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit ContractUnpaused();
    }

    receive() external payable {
        revert("Use openAccount() or deposit() to add funds");
    }

    // Players can withdraw some ETH from their account
    function withdraw(uint256 amount) external nonReentrant hasActiveAccount {
        require(amount > 0, "Must withdraw some ETH");
        require(playerBalances[msg.sender] >= amount, "Insufficient balance");
        
        playerBalances[msg.sender] -= amount;
        
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        emit BalanceUpdated(msg.sender, playerBalances[msg.sender]);
    }
}