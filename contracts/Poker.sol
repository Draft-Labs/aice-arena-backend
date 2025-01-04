// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "./PokerMain.sol";

/**
 * @title Poker
 * @dev This contract is deprecated and exists only for backward compatibility.
 * Please use PokerMain contract for all new integrations.
 */
contract Poker is PokerMain {
    constructor(uint256 _minBetAmount, address payable _treasuryAddress) 
        PokerMain(_minBetAmount, _treasuryAddress) {}
}
            // Emit events
            emit HandComplete(tableId, winner, potAmount);
            emit HandWinner(tableId, winner, highestRank, potAmount);
        }
        
        table.gameState = GameState.Complete;
        
        // Start new hand if enough players
        if (table.playerCount >= 2) {
            startNewHand(tableId);
        } else {
            table.gameState = GameState.Waiting;
        }
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
        GameState gameState,
        bool isActive
    ) {
        Table storage table = tables[tableId];
        return (
            table.minBuyIn,
            table.maxBuyIn,
            table.smallBlind,
            table.bigBlind,
            table.minBet,
            table.maxBet,
            table.pot,
            table.playerCount,
            table.gameState,
            table.isActive
        );
    }

    function getPlayerInfo(uint256 tableId, address player) external view returns (
        uint256 tableStake,
        uint256 currentBet,
        bool isActive,
        bool isSittingOut,
        uint256 position
    ) {
        Player storage p = tables[tableId].players[player];
        return (
            p.tableStake,
            p.currentBet,
            p.isActive,
            p.isSittingOut,
            p.position
        );
    }

    // Add function to update bet limits
    function updateTableBetLimits(
        uint256 tableId,
        uint256 newMinBet,
        uint256 newMaxBet
    ) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.isActive, "Table not active");
        require(table.gameState == GameState.Waiting, "Game in progress");
        
        if (newMinBet >= newMaxBet) revert InvalidBetLimits();
        if (newMinBet < table.bigBlind) revert InvalidBetLimits();
        if (newMaxBet > table.maxBuyIn) revert InvalidBetLimits();

        table.minBet = newMinBet;
        table.maxBet = newMaxBet;

        emit TableConfigUpdated(tableId, newMinBet, newMaxBet);
    }

    // Add this function to get all players at a table
    function getTablePlayers(uint256 tableId) external view returns (address[] memory) {
        Table storage table = tables[tableId];
        return table.playerAddresses;
    }

    function check(uint256 tableId) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        Table storage table = tables[tableId];
        Player storage player = table.players[msg.sender];
        
        require(table.currentPosition == player.position, "Not your turn");
        require(player.currentBet == table.currentBet, "Cannot check");
        
        table.hasActed[player.position] = true;
        
        emit TurnEnded(tableId, msg.sender, "check");
        moveToNextPlayer(tableId);
    }

    function call(uint256 tableId) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        Table storage table = tables[tableId];
        Player storage player = table.players[msg.sender];
        
        require(table.currentPosition == player.position, "Not your turn");
        
        uint256 callAmount = table.currentBet - player.currentBet;
        require(callAmount <= player.tableStake, "Insufficient funds");
        
        player.tableStake -= callAmount;
        player.currentBet = table.currentBet;
        table.pot += callAmount;
        table.hasActed[player.position] = true;
        
        emit BetPlaced(tableId, msg.sender, callAmount);
        emit TurnEnded(tableId, msg.sender, "call");
        
        moveToNextPlayer(tableId);
    }

    function startFlop(uint256 tableId) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.PreFlop, "Not in PreFlop state");
        require(checkRoundComplete(tableId), "Not all players have acted");
        
        
        // Deal flop cards
        uint8[] memory flopCards = new uint8[](3);
        flopCards[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop1"))) % 52 + 1);
        flopCards[1] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop2"))) % 52 + 1);
        flopCards[2] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop3"))) % 52 + 1);
        
        // Store cards directly
        table.communityCards = flopCards;
        
        // Change game state
        table.gameState = GameState.Flop;
        
        emit CommunityCardsDealt(tableId, flopCards);
    }

    function startTurn(uint256 tableId) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.Flop, "Not in Flop state");
        require(checkRoundComplete(tableId), "Not all players have acted");

        // Deal turn card
        uint8 turnCard = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "turn"))) % 52 + 1);
        
        // Add turn card to community cards
        table.communityCards.push(turnCard);
        
        // Change game state
        table.gameState = GameState.Turn;
        
        emit CommunityCardsDealt(tableId, table.communityCards);
    }

    function startRiver(uint256 tableId) external onlyOwner {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.Turn, "Not in Turn state");
        require(checkRoundComplete(tableId), "Not all players have acted");

        // Deal river card
        uint8 riverCard = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "river"))) % 52 + 1);
        
        // Add river card to community cards
        table.communityCards.push(riverCard);
        
        // Change game state
        table.gameState = GameState.River;
        
        emit CommunityCardsDealt(tableId, table.communityCards);
    }

    function startShowdown(uint256 tableId) 
        external 
        onlyOwner 
        onlyValidTable(tableId) 
    {
        Table storage table = tables[tableId];
        require(table.gameState == GameState.River, "Invalid game state");
        require(checkRoundComplete(tableId), "Not all players have acted");

        table.gameState = GameState.Showdown;
        determineWinner(tableId);
    }

    // Helper function to reset bets between rounds
    function resetBets(uint256 tableId) internal {
        Table storage table = tables[tableId];
        
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            if (table.players[playerAddr].isActive) {
                table.players[playerAddr].currentBet = 0;
            }
        }
    }

    function dealPlayerCards(uint256 tableId, address player, uint8[] memory cards) 
        internal 
        onlyValidTable(tableId) 
    {
        require(cards.length == 2, "Must deal exactly 2 cards");
        Table storage table = tables[tableId];
        require(table.players[player].isActive, "Player not active");
        
        delete table.playerCards[player];
        for (uint i = 0; i < cards.length; i++) {
            table.playerCards[player].push(cards[i]);
        }
        
        emit CardsDealt(tableId, player, cards);
    }

    function dealCommunityCards(uint256 tableId, uint8[] memory cards) 
        internal 
        onlyValidTable(tableId) 
    {
        Table storage table = tables[tableId];
        
        // Store the cards
        for (uint i = 0; i < cards.length; i++) {
            table.communityCards.push(cards[i]);
        }
        
        emit CommunityCardsDealt(tableId, cards);
    }

    function getPlayerCards(uint256 tableId, address player) 
        public 
        view 
        returns (uint8[] memory) 
    {
        require(msg.sender == player || msg.sender == owner(), "Not authorized");
        return tables[tableId].playerCards[player];
    }

    function getCommunityCards(uint256 tableId) 
        public 
        view 
        returns (uint8[] memory) 
    {
        return tables[tableId].communityCards;
    }

    // Internal helper function
    function _placeBet(uint256 tableId, address player, uint256 amount) internal {
        Table storage table = tables[tableId];
        Player storage playerInfo = table.players[player];
        
        require(playerInfo.tableStake >= amount, "Insufficient balance");
        
        playerInfo.tableStake -= amount;
        playerInfo.currentBet = amount;
        table.pot += amount;
        
        emit BetPlaced(tableId, player, amount);
    }

    function _awardPot(uint256 tableId, address winner) internal {
        Table storage table = tables[tableId];
        Player storage player = table.players[winner];
        
        // Log before award
        console.log("Awarding pot to winner:", winner);
        console.log("Pot amount:", table.pot);
        
        // Add pot to winner's table stake
        player.tableStake += table.pot;
        
        // Reset pot
        uint256 potAmount = table.pot;
        table.pot = 0;
        
        // Get winner's hand rank
        uint8[] memory playerCards = table.playerCards[winner];
        uint8[] memory allCards = new uint8[](7);
        
        // Combine player cards and community cards
        allCards[0] = playerCards[0];
        allCards[1] = playerCards[1];
        for(uint j = 0; j < table.communityCards.length; j++) {
            allCards[j + 2] = table.communityCards[j];
        }
        
        // Evaluate hand
        (HandRank winningRank, ) = evaluateHand(allCards);
        
        // Log after award
        console.log("Pot awarded, emitting event");
        
        // Only emit HandComplete for game state tracking
        emit HandComplete(tableId, winner, potAmount);
        // Emit HandWinner with the actual hand rank
        emit HandWinner(tableId, winner, winningRank, potAmount);
        
        console.log("Events emitted");
    }

    function checkRoundComplete(uint256 tableId) internal view returns (bool) {
        Table storage table = tables[tableId];
        uint256 activeCount = 0;
        uint256 targetBet = table.currentBet;
        
        for (uint i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            Player storage player = table.players[playerAddr];
            
            if (player.isActive) {
                activeCount++;
                if (!table.hasActed[i] || player.currentBet != targetBet) {
                    return false;
                }
            }
        }
        
        return activeCount >= 2;
    }

    function raise(uint256 tableId, uint256 amount) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        Table storage table = tables[tableId];
        Player storage player = table.players[msg.sender];
        
        require(table.currentPosition == player.position, "Not your turn");
        require(amount > table.currentBet * 2, "Raise must be at least double current bet");
        require(amount <= player.tableStake, "Insufficient funds");
        require(amount >= table.minBet && amount <= table.maxBet, "Invalid bet amount");
        
        player.tableStake -= amount;
        player.currentBet = amount;
        table.currentBet = amount;
        table.pot += amount;
        table.hasActed[player.position] = true;
        
        // Reset hasActed for all other players since they need to respond to raise
        for (uint256 i = 0; i < table.playerCount; i++) {
            if (i != player.position) {
                table.hasActed[i] = false;
            }
        }
        
        emit BetPlaced(tableId, msg.sender, amount);
        emit TurnEnded(tableId, msg.sender, "raise");
        
        moveToNextPlayer(tableId);
    }

    // Add this new helper function
    function resetRound(uint256 tableId) internal {
        Table storage table = tables[tableId];
        
        // Reset hasActed flags
        for (uint256 i = 0; i < table.playerCount; i++) {
            table.hasActed[i] = false;
        }
        
        // Only reset current bets if the hand is complete
        if (table.gameState == GameState.Complete || table.gameState == GameState.Waiting) {
            // Reset current bets
            for (uint i = 0; i < table.playerAddresses.length; i++) {
                address playerAddr = table.playerAddresses[i];
                if (table.players[playerAddr].isActive) {
                    table.players[playerAddr].currentBet = 0;
                }
            }
            
            // Reset table current bet
            table.currentBet = 0;
        }
        
        // Reset current position to first active player
        for (uint256 i = 0; i < table.playerAddresses.length; i++) {
            address playerAddr = table.playerAddresses[i];
            if (table.players[playerAddr].isActive) {
                table.currentPosition = i;
                break;
            }
        }
    }
}
