// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./HouseTreasury.sol";
import "./PokerEvents.sol";
import "./PokerTable.sol";
import "./PokerHandEval.sol";
import "./PokerGameplay.sol";

contract PokerMain is PokerGameplay {
    // Configuration
    address payable public treasuryAddress;

    constructor(
        uint256 _minBetAmount, 
        address payable _treasuryAddress
    ) 
        PokerGameplay(_minBetAmount, _treasuryAddress)
    {}

    // Table creation
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet
    ) public override onlyOwner returns (uint256) {
        return super.createTable(minBuyIn, maxBuyIn, smallBlind, bigBlind, minBet, maxBet);
    }

    // Join table
    function joinTable(uint256 tableId, uint256 buyInAmount) public override nonReentrant {
        require(
            treasury.getPlayerBalance(msg.sender) >= buyInAmount,
            "Insufficient balance in treasury"
        );

        // Process buy-in through treasury
        HouseTreasury(treasuryAddress).processBetLoss(msg.sender, buyInAmount);
        
        // Join table through inherited function
        super.joinTable(tableId, buyInAmount);
        playerTables[msg.sender] = tableId;

        // Start game if enough players
        if (super.getPlayerCount(tableId) >= 2) {
            super.startNewHand(tableId);
        }
    }

    // Leave table
    function leaveTable(uint256 tableId) public override nonReentrant {
        require(playerTables[msg.sender] == tableId, "Player not at this table");
        
        uint256 remainingStake = super.getPlayerTableStake(tableId, msg.sender);
        if (remainingStake > 0) {
            HouseTreasury(treasuryAddress).processBetWin(msg.sender, remainingStake);
        }
        
        super.leaveTable(tableId);
        delete playerTables[msg.sender];
    }

    // Game actions
    function placeBet(uint256 tableId, uint256 betAmount) public override {
        super.placeBet(tableId, betAmount);
    }

    function fold(uint256 tableId) public override {
        super.fold(tableId);
    }

    function check(uint256 tableId) public override {
        super.check(tableId);
    }

    function call(uint256 tableId) public override {
        super.call(tableId);
    }

    // View functions
    function getTableInfo(uint256 tableId) public view override returns (
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
        return super.getTableInfo(tableId);
    }

    function getPlayerInfo(uint256 tableId, address player) public view override returns (
        uint256 tableStake,
        uint256 currentBet,
        bool isActive,
        bool isSittingOut,
        uint256 position
    ) {
        return super.getPlayerInfo(tableId, player);
    }

    function getTablePlayers(uint256 tableId) public view override returns (address[] memory) {
        return super.getTablePlayers(tableId);
    }
}
