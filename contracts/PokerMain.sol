// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./PokerTables.sol";
import "./PokerFunctionality.sol";
import "./HouseTreasury.sol";

/**
 * @title PokerMain
 * @dev Main contract for the web3 poker game that combines table management and gameplay functionality
 */
contract PokerMain is Ownable, ReentrancyGuard {
    PokerTables public pokerTables;
    PokerFunctionality public pokerFunctionality;
    HouseTreasury public treasury;

    constructor(address payable _treasuryAddress) Ownable(msg.sender) {
        treasury = HouseTreasury(_treasuryAddress);
        
        // Create and deploy PokerTables contract
        pokerTables = new PokerTables(0.01 ether, _treasuryAddress);
        
        // Create and deploy PokerFunctionality contract
        pokerFunctionality = new PokerFunctionality(address(pokerTables));

        // Log deployment info
        console.log("PokerMain deployed. Treasury:", _treasuryAddress);
        console.log("PokerTables deployed at:", address(pokerTables));
        console.log("PokerFunctionality deployed at:", address(pokerFunctionality));
    }

    /**
     * @dev Create a new poker table
     */
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet
    ) external onlyOwner returns (uint256) {
        return pokerTables.createTable(
            minBuyIn,
            maxBuyIn,
            smallBlind,
            bigBlind,
            minBet,
            maxBet
        );
    }

    /**
     * @dev Player joins a table
     */
    function joinTable(uint256 tableId, uint256 buyInAmount) external {
        pokerTables.joinTable(tableId, buyInAmount);
    }
    
    /**
     * @dev Admin joins a table for a specific player (testing only)
     */
    function joinTableForPlayer(uint256 tableId, uint256 buyInAmount, address player) external onlyOwner {
        pokerTables.joinTableForPlayer(tableId, buyInAmount, player);
    }

    /**
     * @dev Player leaves a table
     */
    function leaveTable(uint256 tableId) external {
        pokerTables.leaveTable(tableId);
    }
    
    /**
     * @dev Admin removes a player from a table (testing only)
     */
    function leaveTableForPlayer(uint256 tableId, address player) external onlyOwner {
        pokerTables.leaveTableForPlayer(tableId, player);
    }

    /**
     * @dev Player places a bet
     */
    function placeBet(uint256 tableId, uint256 betAmount) external {
        pokerFunctionality.placeBet(tableId, betAmount);
    }

    /**
     * @dev Player folds
     */
    function fold(uint256 tableId) external {
        pokerFunctionality.fold(tableId);
    }

    /**
     * @dev Player checks
     */
    function check(uint256 tableId) external {
        pokerFunctionality.check(tableId);
    }

    /**
     * @dev Player calls
     */
    function call(uint256 tableId) external {
        pokerFunctionality.call(tableId);
    }

    /**
     * @dev Player raises
     */
    function raise(uint256 tableId, uint256 amount) external {
        pokerFunctionality.raise(tableId, amount);
    }

    /**
     * @dev Get table information
     */
    function getTableInfo(uint256 tableId) external view returns (
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet,
        uint256 pot,
        uint256 playerCount,
        IPokerTables.GameState gameState,
        bool isActive
    ) {
        return pokerTables.getTableInfo(tableId);
    }

    /**
     * @dev Get player information at a table
     */
    function getPlayerInfo(uint256 tableId, address player) external view returns (
        uint256 tableStake,
        uint256 currentBet,
        bool isActive,
        bool isSittingOut,
        uint256 position
    ) {
        return pokerTables.getPlayerInfo(tableId, player);
    }

    /**
     * @dev Get a list of players at a table
     */
    function getTablePlayers(uint256 tableId) external view returns (address[] memory) {
        return pokerTables.getTablePlayers(tableId);
    }

    /**
     * @dev Get a player's cards
     */
    function getPlayerCards(uint256 tableId, address player) external view returns (uint8[] memory) {
        return pokerFunctionality.getPlayerCards(tableId, player);
    }

    /**
     * @dev Get community cards
     */
    function getCommunityCards(uint256 tableId) external view returns (uint8[] memory) {
        return pokerFunctionality.getCommunityCards(tableId);
    }

    /**
     * @dev Update table bet limits
     */
    function updateTableBetLimits(
        uint256 tableId,
        uint256 newMinBet,
        uint256 newMaxBet
    ) external onlyOwner {
        pokerTables.updateTableBetLimits(tableId, newMinBet, newMaxBet);
    }

    /**
     * @dev Admin function to start a new hand
     */
    function startNewHand(uint256 tableId) external onlyOwner {
        pokerFunctionality.startNewHand(tableId);
    }

    /**
     * @dev Admin function to post blinds
     */
    function postBlinds(uint256 tableId) external onlyOwner {
        pokerFunctionality.postBlinds(tableId);
    }

    /**
     * @dev Admin function to start the flop round
     */
    function startFlop(uint256 tableId) external onlyOwner {
        pokerFunctionality.startFlop(tableId);
    }

    /**
     * @dev Admin function to start the turn round
     */
    function startTurn(uint256 tableId) external onlyOwner {
        pokerFunctionality.startTurn(tableId);
    }

    /**
     * @dev Admin function to start the river round
     */
    function startRiver(uint256 tableId) external onlyOwner {
        pokerFunctionality.startRiver(tableId);
    }

    /**
     * @dev Admin function to start the showdown
     */
    function startShowdown(uint256 tableId) external onlyOwner {
        pokerFunctionality.startShowdown(tableId);
    }
    
    /**
     * @dev Function to get player's treasury balance
     */
    function getPlayerTreasuryBalance(address player) external view returns (uint256) {
        return treasury.getPlayerBalance(player);
    }
} 