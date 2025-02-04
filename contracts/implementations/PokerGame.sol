// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPokerGame.sol";
import "./PokerBase.sol";
import "./PokerHand.sol";

contract PokerGame is IPokerGame, PokerBase {
    PokerHand private pokerHand;

    constructor(address storageAddress, address pokerHandAddress) PokerBase(storageAddress) {
        pokerHand = PokerHand(pokerHandAddress);
    }

    // Game actions
    function placeBet(uint256 tableId, uint256 amount) external onlyValidTable(tableId) onlyTablePlayer(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, msg.sender);
        
        require(config.currentPosition == player.position, "Not your turn");
        require(amount <= player.tableStake, "Insufficient funds");
        require(amount >= config.minBet && amount <= config.maxBet, "Invalid bet amount");
        
        player.currentBet = uint40(amount);
        player.tableStake -= uint40(amount);
        config.pot += uint40(amount);
        config.currentBet = uint40(amount);
        
        storage_.setPlayerHasActed(tableId, player.position, true);
        storage_.setPlayer(tableId, msg.sender, player);
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized game action event (Bet)
        emit GameAction(
            tableId,
            msg.sender,
            0, // 0 = Bet
            uint40(amount),
            uint40(config.pot)
        );
        
        moveToNextPlayer(tableId);
    }

    function fold(uint256 tableId) external onlyValidTable(tableId) onlyTablePlayer(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, msg.sender);
        
        require(config.currentPosition == player.position, "Not your turn");
        
        player.isActive = false;
        storage_.setPlayerHasActed(tableId, player.position, true);
        storage_.setPlayer(tableId, msg.sender, player);
        
        // Emit optimized game action event (Fold)
        emit GameAction(
            tableId,
            msg.sender,
            4, // 4 = Fold
            0,
            uint40(config.pot)
        );
        
        moveToNextPlayer(tableId);
    }

    function call(uint256 tableId) external onlyValidTable(tableId) onlyTablePlayer(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, msg.sender);
        
        require(config.currentPosition == player.position, "Not your turn");
        
        uint256 callAmount = config.currentBet - player.currentBet;
        require(callAmount <= player.tableStake, "Insufficient funds");
        
        player.tableStake -= uint40(callAmount);
        player.currentBet = uint40(config.currentBet);
        config.pot += uint40(callAmount);
        
        storage_.setPlayerHasActed(tableId, player.position, true);
        storage_.setPlayer(tableId, msg.sender, player);
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized game action event (Call)
        emit GameAction(
            tableId,
            msg.sender,
            1, // 1 = Call
            uint40(callAmount),
            uint40(config.pot)
        );
        
        moveToNextPlayer(tableId);
    }

    function raise(uint256 tableId, uint256 amount) external onlyValidTable(tableId) onlyTablePlayer(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, msg.sender);
        
        require(config.currentPosition == player.position, "Not your turn");
        require(amount > config.currentBet, "Must raise more than current bet");
        require(amount <= player.tableStake, "Insufficient funds");
        require(amount >= config.minBet && amount <= config.maxBet, "Invalid bet amount");
        
        uint256 raiseAmount = amount - player.currentBet;
        player.tableStake -= uint40(raiseAmount);
        player.currentBet = uint40(amount);
        config.currentBet = uint40(amount);
        config.pot += uint40(raiseAmount);
        
        storage_.setPlayerHasActed(tableId, player.position, true);
        
        // Reset hasActed for all other players since they need to respond to raise
        for (uint256 i = 0; i < config.playerCount; i++) {
            if (i != player.position) {
                storage_.setPlayerHasActed(tableId, i, false);
            }
        }
        
        storage_.setPlayer(tableId, msg.sender, player);
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized game action event (Raise)
        emit GameAction(
            tableId,
            msg.sender,
            2, // 2 = Raise
            uint40(raiseAmount),
            uint40(config.pot)
        );
        
        moveToNextPlayer(tableId);
    }

    function check(uint256 tableId) external onlyValidTable(tableId) onlyTablePlayer(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, msg.sender);
        
        require(config.currentPosition == player.position, "Not your turn");
        require(player.currentBet == config.currentBet, "Cannot check");
        
        storage_.setPlayerHasActed(tableId, player.position, true);
        
        // Emit optimized game action event (Check)
        emit GameAction(
            tableId,
            msg.sender,
            3, // 3 = Check
            0,
            uint40(config.pot)
        );
        
        moveToNextPlayer(tableId);
    }

    // Game state transitions
    function startFlop(uint256 tableId) external onlyOwner onlyValidTable(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(config.gameState == PokerStorage.GameState.PreFlop, "Not in PreFlop state");
        require(isRoundComplete(tableId), "Round not complete");
        
        resetRound(tableId);
        config.gameState = PokerStorage.GameState.Flop;
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized round state event (Flop)
        emit RoundState(
            tableId,
            1, // 1 = Flop
            uint40(config.pot),
            uint8(getActivePlayerCount(tableId))
        );
    }

    function startTurn(uint256 tableId) external onlyOwner onlyValidTable(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(config.gameState == PokerStorage.GameState.Flop, "Not in Flop state");
        require(isRoundComplete(tableId), "Round not complete");
        
        resetRound(tableId);
        config.gameState = PokerStorage.GameState.Turn;
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized round state event (Turn)
        emit RoundState(
            tableId,
            2, // 2 = Turn
            uint40(config.pot),
            uint8(getActivePlayerCount(tableId))
        );
    }

    function startRiver(uint256 tableId) external onlyOwner onlyValidTable(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(config.gameState == PokerStorage.GameState.Turn, "Not in Turn state");
        require(isRoundComplete(tableId), "Round not complete");
        
        resetRound(tableId);
        config.gameState = PokerStorage.GameState.River;
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized round state event (River)
        emit RoundState(
            tableId,
            3, // 3 = River
            uint40(config.pot),
            uint8(getActivePlayerCount(tableId))
        );
    }

    function startShowdown(uint256 tableId) external onlyOwner onlyValidTable(tableId) {
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
        
        // Award pot to winner
        PokerStorage.PackedPlayer memory winningPlayer = storage_.getPlayer(tableId, winner);
        winningPlayer.tableStake += config.pot;
        storage_.setPlayer(tableId, winner, winningPlayer);
        
        // Emit optimized game result event
        emit GameResult(
            tableId,
            winner,
            uint8(winningRank),
            uint40(config.pot),
            uint40(config.pot)
        );
        
        config.pot = 0;
        config.gameState = PokerStorage.GameState.Complete;
        storage_.setTableConfig(tableId, config);
    }

    function startNewHand(uint256 tableId) external onlyOwner onlyValidTable(tableId) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        require(config.gameState == PokerStorage.GameState.Complete || config.gameState == PokerStorage.GameState.Waiting, "Invalid game state");
        
        // Reset game state
        config.gameState = PokerStorage.GameState.PreFlop;
        config.pot = 0;
        config.currentBet = 0;
        config.dealerPosition = uint8((config.dealerPosition + 1) % config.playerCount);
        config.currentPosition = uint8((config.dealerPosition + 1) % config.playerCount);
        
        // Reset all player states
        address[] memory tablePlayers = storage_.getTablePlayers(tableId);
        for (uint i = 0; i < tablePlayers.length; i++) {
            PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, tablePlayers[i]);
            player.currentBet = 0;
            player.isActive = !player.isSittingOut && player.tableStake > 0;
            storage_.setPlayer(tableId, tablePlayers[i], player);
            storage_.setPlayerHasActed(tableId, i, false);
        }
        
        storage_.setTableConfig(tableId, config);
        
        // Emit optimized round state event (PreFlop)
        emit RoundState(
            tableId,
            0, // 0 = PreFlop
            0,
            uint8(getActivePlayerCount(tableId))
        );
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

    // Game state queries
    function isPlayerTurn(uint256 tableId, address player) external view returns (bool) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        PokerStorage.PackedPlayer memory playerInfo = storage_.getPlayer(tableId, player);
        return config.currentPosition == playerInfo.position;
    }

    function getCurrentBet(uint256 tableId) external view returns (uint256) {
        return storage_.getTableConfig(tableId).currentBet;
    }

    function getPot(uint256 tableId) external view returns (uint256) {
        return storage_.getTableConfig(tableId).pot;
    }

    function getGameState(uint256 tableId) external view returns (GameState) {
        return storage_.getTableConfig(tableId).gameState;
    }

    function getCurrentPosition(uint256 tableId) external view returns (uint256) {
        return storage_.getTableConfig(tableId).currentPosition;
    }

    function getDealerPosition(uint256 tableId) external view returns (uint256) {
        return storage_.getTableConfig(tableId).dealerPosition;
    }

    function hasPlayerActed(uint256 tableId, uint256 position) external view returns (bool) {
        return storage_.getPlayerHasActed(tableId, position);
    }

    function isRoundComplete(uint256 tableId) public view returns (bool) {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        uint256 activeCount = 0;
        uint256 actedCount = 0;
        uint256 targetBet = config.currentBet;
        
        address[] memory tablePlayers = storage_.getTablePlayers(tableId);
        for (uint i = 0; i < tablePlayers.length; i++) {
            PokerStorage.PackedPlayer memory player = storage_.getPlayer(tableId, tablePlayers[i]);
            if (player.isActive) {
                activeCount++;
                if (storage_.getPlayerHasActed(tableId, i) && player.currentBet == targetBet) {
                    actedCount++;
                }
            }
        }
        
        return activeCount >= 2 && actedCount == activeCount;
    }

    // Internal helpers
    function moveToNextPlayer(uint256 tableId) internal {
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        address[] memory tablePlayers = storage_.getTablePlayers(tableId);
        
        uint256 startingPosition = config.currentPosition;
        bool foundNext = false;
        
        // Try to find next active player
        for (uint256 i = 1; i <= tablePlayers.length; i++) {
            uint256 nextPosition = (startingPosition + i) % tablePlayers.length;
            address nextPlayer = tablePlayers[nextPosition];
            
            if (storage_.getPlayer(tableId, nextPlayer).isActive) {
                config.currentPosition = uint8(nextPosition);
                foundNext = true;
                storage_.setTableConfig(tableId, config);
                emit TurnStarted(tableId, nextPlayer);
                break;
            }
        }
        
        if (!foundNext || isRoundComplete(tableId)) {
            emit RoundComplete(tableId);
        }
    }

    function resetRound(uint256 tableId) internal {
        storage_.resetRoundState(tableId);
        
        PokerStorage.TableConfig memory config = storage_.getTableConfig(tableId);
        address[] memory tablePlayers = storage_.getTablePlayers(tableId);
        
        // Reset current position to first active player
        for (uint256 i = 0; i < tablePlayers.length; i++) {
            if (storage_.getPlayer(tableId, tablePlayers[i]).isActive) {
                config.currentPosition = uint8(i);
                break;
            }
        }
        
        storage_.setTableConfig(tableId, config);
    }
} 