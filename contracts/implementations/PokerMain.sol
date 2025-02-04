// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PokerGame.sol";
import "./PokerTable.sol";
import "./PokerHand.sol";
import "./PokerTreasury.sol";

contract PokerMain is PokerGame, PokerTable {
    PokerTreasury public immutable treasury;

    constructor(
        address storageAddress,
        address treasuryAddress,
        address pokerHandAddress
    ) PokerGame(storageAddress, pokerHandAddress) {
        treasury = PokerTreasury(treasuryAddress);
    }

    // Override table functions to handle treasury integration
    function joinTable(uint256 tableId, uint256 buyInAmount) external override {
        // Validate buy-in amount
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(buyInAmount >= config.minBuyIn && buyInAmount <= config.maxBuyIn, "Invalid buy-in amount");
        
        // Check if player has sufficient balance in treasury
        require(
            treasury.getBalance(msg.sender) >= buyInAmount,
            "Insufficient balance in treasury"
        );

        // Transfer buy-in from player's treasury balance
        balances[msg.sender] = balances[msg.sender].sub(buyInAmount);
        totalFunds = totalFunds.sub(buyInAmount);

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
            balances[msg.sender] = balances[msg.sender].add(remainingStake);
            totalFunds = totalFunds.add(remainingStake);
        }
    }

    // Override game functions to handle treasury integration
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
        
        // Calculate and collect house fee
        uint256 fee = treasury.collectHouseFee(config.pot);
        uint256 winnings = config.pot.sub(fee);
        
        // Award winnings to winner through treasury
        balances[winner] = balances[winner].add(winnings);
        totalFunds = totalFunds.add(winnings);
        
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

    // Treasury integration functions
    function deposit() external payable {
        treasury.deposit{value: msg.value}();
    }

    function requestWithdrawal(uint256 amount) external {
        treasury.requestWithdrawal(amount);
    }

    function getPlayerBalance() external view returns (uint256) {
        return treasury.getBalance(msg.sender);
    }

    // Emergency functions
    function emergencyWithdraw() external whenPaused {
        uint256 tableId = storage_.getPlayerTableId(msg.sender);
        if (tableId != 0) {
            super.emergencyWithdraw(tableId, msg.sender);
        }
        treasury.emergencyWithdraw(msg.sender);
    }

    // Receive function to handle incoming funds
    receive() external payable {
        deposit();
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
} 