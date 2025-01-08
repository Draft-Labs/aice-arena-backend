// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IPokerTable.sol";
import "../HouseTreasury.sol";

/**
 * @title PokerBetting
 * @dev Contract for managing poker betting functionality
 */
contract PokerBetting is Ownable, ReentrancyGuard {
    IPokerTable public pokerTable;
    HouseTreasury public treasury;

    // Events
    event BetPlaced(uint256 indexed tableId, address indexed player, uint256 amount);
    event BlindsPosted(uint256 indexed tableId, address smallBlind, address bigBlind, uint256 smallBlindAmount, uint256 bigBlindAmount);
    event PotAwarded(uint256 indexed tableId, address indexed winner, uint256 amount);

    // Error messages
    error InvalidBetAmount();
    error InsufficientBalance();
    error NotYourTurn();
    error InvalidGameState();
    error CannotCheck();
    error BetProcessingFailed();
    error NotInitialized();

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
     * @dev Places a bet for a player
     */
    function placeBet(uint256 tableId, uint256 betAmount) external nonReentrant {
        // Get table info
        (
            ,
            ,
            ,
            ,
            uint256 minBet,
            uint256 maxBet,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Get player info
        (uint256 tableStake,, bool isActive,,) = pokerTable.getPlayerInfo(tableId, msg.sender);

        // Validate bet
        if (!isActive) revert NotYourTurn();
        if (!pokerTable.isPlayerTurn(tableId, msg.sender)) revert NotYourTurn();
        if (betAmount < minBet || betAmount > maxBet) revert InvalidBetAmount();
        if (betAmount > tableStake) revert InsufficientBalance();
        if (gameState == IPokerTable.GameState.Waiting || 
            gameState == IPokerTable.GameState.Complete) revert InvalidGameState();

        // Process bet
        _processBet(tableId, msg.sender, betAmount);

        emit BetPlaced(tableId, msg.sender, betAmount);
    }

    /**
     * @dev Allows a player to call the current bet
     */
    function call(uint256 tableId) external nonReentrant {
        // Get table info
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Get player info
        (uint256 tableStake, uint256 currentBet, bool isActive,,) = pokerTable.getPlayerInfo(tableId, msg.sender);

        // Validate call
        if (!isActive) revert NotYourTurn();
        if (gameState == IPokerTable.GameState.Waiting || 
            gameState == IPokerTable.GameState.Complete) revert InvalidGameState();

        uint256 callAmount = getCurrentBet(tableId) - currentBet;
        if (callAmount > tableStake) revert InsufficientBalance();

        // Process call
        _processBet(tableId, msg.sender, callAmount);

        emit BetPlaced(tableId, msg.sender, callAmount);
    }

    /**
     * @dev Allows a player to check (bet 0)
     */
    function check(uint256 tableId) external nonReentrant {
        // Get player info
        (, uint256 currentBet, bool isActive,,) = pokerTable.getPlayerInfo(tableId, msg.sender);

        // Validate check
        if (!isActive) revert NotYourTurn();
        if (currentBet != getCurrentBet(tableId)) revert CannotCheck();

        emit BetPlaced(tableId, msg.sender, 0);
    }

    /**
     * @dev Allows a player to raise the current bet
     */
    function raise(uint256 tableId, uint256 raiseAmount) external nonReentrant {
        // Get table info
        (
            ,
            ,
            ,
            ,
            ,
            uint256 maxBet,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        // Get player info
        (uint256 tableStake,, bool isActive,,) = pokerTable.getPlayerInfo(tableId, msg.sender);

        // Validate raise
        if (!isActive) revert NotYourTurn();
        if (gameState == IPokerTable.GameState.Waiting || 
            gameState == IPokerTable.GameState.Complete) revert InvalidGameState();

        uint256 currentTableBet = getCurrentBet(tableId);
        if (raiseAmount <= currentTableBet * 2) revert InvalidBetAmount();
        if (raiseAmount > maxBet) revert InvalidBetAmount();
        if (raiseAmount > tableStake) revert InsufficientBalance();

        // Process raise
        _processBet(tableId, msg.sender, raiseAmount);

        emit BetPlaced(tableId, msg.sender, raiseAmount);
    }

    /**
     * @dev Posts blinds for a new hand
     */
    function postBlinds(uint256 tableId) external onlyOwner {
        // Get table info
        (
            ,
            ,
            uint256 smallBlindAmount,
            uint256 bigBlindAmount,
            ,
            ,
            ,
            ,
            IPokerTable.GameState gameState
        ) = pokerTable.getTableInfo(tableId);

        require(gameState == IPokerTable.GameState.PreFlop, "Not in PreFlop state");

        address[] memory players = pokerTable.getTablePlayers(tableId);
        require(players.length >= 2, "Need at least 2 players");

        // Post small blind (Player 0)
        address smallBlindPlayer = players[0];
        _processBet(tableId, smallBlindPlayer, smallBlindAmount);

        // Post big blind (Player 1)
        address bigBlindPlayer = players[1];
        _processBet(tableId, bigBlindPlayer, bigBlindAmount);

        emit BlindsPosted(tableId, smallBlindPlayer, bigBlindPlayer, smallBlindAmount, bigBlindAmount);
    }

    /**
     * @dev Awards the pot to the winner
     */
    function awardPot(uint256 tableId, address winner) external onlyOwner {
        (,,,,,, uint256 pot,,) = pokerTable.getTableInfo(tableId);
        require(pot > 0, "No pot to award");

        // Transfer pot to winner's stake
        _processWin(tableId, winner, pot);

        emit PotAwarded(tableId, winner, pot);
    }

    /**
     * @dev Gets the current bet amount for a table
     */
    function getCurrentBet(uint256 tableId) public view returns (uint256) {
        address[] memory players = pokerTable.getTablePlayers(tableId);
        uint256 maxBet = 0;

        for (uint i = 0; i < players.length; i++) {
            (,uint256 currentBet,,,) = pokerTable.getPlayerInfo(tableId, players[i]);
            if (currentBet > maxBet) {
                maxBet = currentBet;
            }
        }

        return maxBet;
    }

    // Internal functions
    function _processBet(uint256 tableId, address player, uint256 amount) internal {
        // Get current player info
        (uint256 tableStake,,,, ) = pokerTable.getPlayerInfo(tableId, player);
        
        // Calculate new stake
        uint256 newStake = tableStake - amount;
        
        // Update player's bet and stake
        bool success = pokerTable.updatePlayerBet(tableId, player, amount, newStake);
        if (!success) revert BetProcessingFailed();
        
        // Update pot
        success = pokerTable.updatePot(tableId, amount);
        if (!success) revert BetProcessingFailed();
        
        // Advance to next player
        pokerTable.advanceToNextPlayer(tableId);
    }

    function _processWin(uint256 tableId, address winner, uint256 amount) internal {
        // Award pot to winner
        bool success = pokerTable.awardPotToPlayer(tableId, winner, amount);
        if (!success) revert BetProcessingFailed();
        
        // Update pot to zero
        success = pokerTable.updatePot(tableId, 0);
        if (!success) revert BetProcessingFailed();
    }
} 