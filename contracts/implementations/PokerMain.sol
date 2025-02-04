// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PokerGame.sol";
import "./PokerTable.sol";
import "./PokerHand.sol";
import "../HouseTreasury.sol";

contract PokerMain is PokerGame, PokerTable {
    HouseTreasury public treasury;

    constructor(
        address storageAddress,
        address treasuryAddress,
        address pokerHandAddress
    ) PokerGame(storageAddress, pokerHandAddress) {
        treasury = HouseTreasury(treasuryAddress);
    }

    // Override table functions to handle treasury integration
    function joinTable(uint256 tableId, uint256 buyInAmount) external override {
        // Check if player has sufficient balance in treasury
        require(
            treasury.getPlayerBalance(msg.sender) >= buyInAmount,
            "Insufficient balance in treasury"
        );

        // Transfer buy-in from player's treasury balance
        treasury.processBetLoss(msg.sender, buyInAmount);

        // Call parent implementation
        super.joinTable(tableId, buyInAmount);
    }

    function leaveTable(uint256 tableId) external override {
        PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, msg.sender);
        uint256 remainingStake = player.tableStake;

        // Call parent implementation first
        super.leaveTable(tableId);

        // Return remaining stake to treasury
        if (remainingStake > 0) {
            treasury.processBetWin(msg.sender, remainingStake);
        }
    }

    // Override game functions to handle treasury integration
    function postBlinds(uint256 tableId) external onlyOwner {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(config.gameState == PokerStorage.GameState.PreFlop, "Not in PreFlop state");
        
        uint8 smallBlindPos = uint8((config.dealerPosition + 1) % config.playerCount);
        uint8 bigBlindPos = uint8((config.dealerPosition + 2) % config.playerCount);
        
        address smallBlindPlayer = storage_.getPlayerAtPosition(tableId, smallBlindPos);
        address bigBlindPlayer = storage_.getPlayerAtPosition(tableId, bigBlindPos);
        
        PokerStorage.PackedPlayer memory smallBlind = storage_.getPlayer(tableId, smallBlindPlayer);
        PokerStorage.PackedPlayer memory bigBlind = storage_.getPlayer(tableId, bigBlindPlayer);
        
        uint256 smallBlindAmount = config.minBet / 2;
        uint256 bigBlindAmount = config.minBet;
        
        require(smallBlind.tableStake >= smallBlindAmount, "Small blind insufficient funds");
        require(bigBlind.tableStake >= bigBlindAmount, "Big blind insufficient funds");
        
        // Post small blind
        smallBlind.tableStake -= uint40(smallBlindAmount);
        smallBlind.currentBet = uint40(smallBlindAmount);
        config.pot += uint40(smallBlindAmount);
        
        // Post big blind
        bigBlind.tableStake -= uint40(bigBlindAmount);
        bigBlind.currentBet = uint40(bigBlindAmount);
        config.pot += uint40(bigBlindAmount);
        config.currentBet = uint40(bigBlindAmount);
        
        storage_.setPlayer(tableId, smallBlindPlayer, smallBlind);
        storage_.setPlayer(tableId, bigBlindPlayer, bigBlind);
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized blinds posted event
        emit BlindsPosted(
            tableId,
            smallBlindPlayer,
            bigBlindPlayer,
            uint40(smallBlindAmount),
            uint40(bigBlindAmount)
        );
    }

    function startShowdown(uint256 tableId) external override onlyOwner onlyValidTable(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(config.gameState == PokerStorage.GameState.River, "Not in River state");
        require(isRoundComplete(tableId), "Round not complete");
        
        config.gameState = PokerStorage.GameState.Showdown;
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized round state event (Showdown)
        emit RoundState(
            tableId,
            4, // 4 = Showdown
            uint40(config.pot),
            uint8(getActivePlayerCount(tableId))
        );
        
        (address winner, HandRank winningRank, uint256 winningScore) = pokerHand.determineWinner(tableId);
        
        // Transfer pot to treasury
        uint256 fee = (config.pot * treasuryFee) / 10000;
        uint256 winnings = config.pot - fee;
        treasury.transfer(fee);
        
        // Award winnings to winner
        PokerStorage.PackedPlayer memory winningPlayer = storage_.getPlayer(tableId, winner);
        winningPlayer.tableStake += uint40(winnings);
        storage_.setPlayer(tableId, winner, winningPlayer);
        
        // Emit optimized game result event
        emit GameResult(
            tableId,
            winner,
            uint8(winningRank),
            uint40(winnings),
            uint40(fee)
        );
        
        config.pot = 0;
        config.gameState = PokerStorage.GameState.Complete;
        storage_.setTableConfig(tableId, config);
    }

    // Helper function to get active player count
    function getActivePlayerCount(uint256 tableId) internal view returns (uint256 count) {
        address[] memory tablePlayers = storage_.getTablePlayers(tableId);
        for (uint i = 0; i < tablePlayers.length; i++) {
            if (storage_.getPlayer(tableId, tablePlayers[i]).isActive) {
                count++;
            }
        }
        return count;
    }

    // Add function to get player's treasury balance
    function getPlayerBalance(address player) external view returns (uint256) {
        return treasury.getPlayerBalance(player);
    }

    // Add function to check if player has active treasury account
    function hasActiveTreasuryAccount(address player) external view returns (bool) {
        return treasury.activeAccounts(player);
    }
} 