// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./HouseTreasury.sol";
import "./PokerEvents.sol";
import "./PokerTable.sol";
import "./PokerHandEval.sol";
import "./PokerGameplay.sol";

contract PokerMain is Ownable, ReentrancyGuard {
    // Contract references
    HouseTreasury public treasury;
    PokerHandEval public handEvaluator;
    PokerTable public tableManager;
    PokerGameplay public gameManager;

    // Configuration
    uint256 public minBetAmount;
    uint256 public maxTables = 10;
    uint256 public maxPlayersPerTable = 6; // 5 players + house

    // Mappings
    mapping(address => uint256) public playerTables; // Which table a player is at

    // Error messages
    error TableFull();
    error InvalidBuyIn();
    error PlayerNotAtTable();
    error InvalidBetAmount();
    error NotPlayerTurn();
    error InvalidGameState();
    error InsufficientBalance();
    error TableNotActive();
    error InvalidBetLimits();
    error OnlyOwnerAllowed();

    constructor(uint256 _minBetAmount, address payable _treasuryAddress) Ownable(msg.sender) {
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
        
        // Initialize contracts
        handEvaluator = new PokerHandEval();
        tableManager = new PokerTable();
        gameManager = new PokerGameplay(address(handEvaluator), address(tableManager));
    }

    // Table creation
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet
    ) external onlyOwner returns (uint256) {
        return tableManager.createTable(minBuyIn, maxBuyIn, smallBlind, bigBlind, minBet, maxBet);
    }

    // Join table
    function joinTable(uint256 tableId, uint256 buyInAmount) external nonReentrant {
        require(
            treasury.getPlayerBalance(msg.sender) >= buyInAmount,
            "Insufficient balance in treasury"
        );

        // Process buy-in through treasury
        treasury.processBetLoss(msg.sender, buyInAmount);
        
        // Join table through table manager
        tableManager.joinTable(tableId, msg.sender, buyInAmount);
        playerTables[msg.sender] = tableId;

        // Start game if enough players
        if (tableManager.getPlayerCount(tableId) >= 2) {
            gameManager.startNewHand(tableId);
        }
    }

    // Leave table
    function leaveTable(uint256 tableId) external nonReentrant {
        require(playerTables[msg.sender] == tableId, "Player not at this table");
        
        uint256 remainingStake = tableManager.getPlayerTableStake(tableId, msg.sender);
        if (remainingStake > 0) {
            treasury.processBetWin(msg.sender, remainingStake);
        }
        
        tableManager.leaveTable(tableId, msg.sender);
        delete playerTables[msg.sender];
    }

    // Game actions
    function placeBet(uint256 tableId, uint256 betAmount) external {
        gameManager.placeBet(tableId, betAmount);
    }

    function fold(uint256 tableId) external {
        gameManager.fold(tableId);
    }

    function check(uint256 tableId) external {
        gameManager.check(tableId);
    }

    function call(uint256 tableId) external {
        gameManager.call(tableId);
    }

    // View functions
    function getTableInfo(uint256 tableId) external view returns (
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet,
        uint256 pot,
        uint256 playerCount,
        uint8 gameState,
        bool isActive
    ) {
        return tableManager.getTableInfo(tableId);
    }

    function getPlayerInfo(uint256 tableId, address player) external view returns (
        uint256 tableStake,
        uint256 currentBet,
        bool isActive,
        bool isSittingOut,
        uint256 position
    ) {
        return tableManager.getPlayerInfo(tableId, player);
    }

    function getTablePlayers(uint256 tableId) external view returns (address[] memory) {
        return tableManager.getTablePlayers(tableId);
    }
}
