// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./PokerEvents.sol";
import "./PokerTable.sol";
import "./PokerHandEval.sol";

contract PokerGameplay is PokerEvents {
    enum GameState {
        Waiting,    // Waiting for players
        Dealing,    // Cards being dealt
        PreFlop,    // Initial betting round
        Flop,       // After first 3 community cards
        Turn,       // After 4th community card
        River,      // After 5th community card
        Showdown,   // Revealing hands
        Complete    // Game finished
    }

    // References to other contracts
    PokerHandEval private handEvaluator;
    PokerTable private tableManager;

    constructor(address _handEvaluator, address _tableManager) {
        handEvaluator = PokerHandEval(_handEvaluator);
        tableManager = PokerTable(_tableManager);
    }

    modifier onlyValidTable(uint256 tableId) {
        require(tableManager.isTableActive(tableId), "Table does not exist");
        _;
    }

    modifier onlyTablePlayer(uint256 tableId) {
        require(tableManager.isPlayerAtTable(tableId, msg.sender), "Not a player at this table");
        _;
    }

    modifier onlyDuringState(uint256 tableId, GameState state) {
        require(tableManager.getTableState(tableId) == uint8(state), "Invalid game state");
        _;
    }

    // Game flow functions
    function startNewHand(uint256 tableId) internal {
        // Reset game state
        tableManager.setGameState(tableId, GameState.Dealing);
        tableManager.resetTableForNewHand(tableId);
        
        // Deal new cards to active players
        address[] memory players = tableManager.getTablePlayers(tableId);
        for (uint i = 0; i < players.length; i++) {
            address player = players[i];
            if (tableManager.isPlayerActive(tableId, player)) {
                uint8[] memory cards = new uint8[](2);
                cards[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, player, "card1"))) % 52 + 1);
                cards[1] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, player, "card2"))) % 52 + 1);
                dealPlayerCards(tableId, player, cards);
            }
        }

        emit GameStarted(tableId);
    }

    function dealPlayerCards(uint256 tableId, address player, uint8[] memory cards) internal {
        require(cards.length == 2, "Invalid number of cards");
        tableManager.setPlayerCards(tableId, player, cards);
        emit PlayerCardsDealt(tableId, player, cards);
    }

    function fold(uint256 tableId) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        require(tableManager.isPlayerTurn(tableId, msg.sender), "Not your turn");
        require(tableManager.isPlayerActive(tableId, msg.sender), "Player not active");
        
        // Mark player as inactive and record action
        tableManager.setPlayerActive(tableId, msg.sender, false);
        tableManager.setPlayerHasActed(tableId, msg.sender, true);
        
        emit PlayerFolded(tableId, msg.sender);
        emit TurnEnded(tableId, msg.sender, "fold");
        
        moveToNextPlayer(tableId);
    }

    function placeBet(uint256 tableId, uint256 betAmount) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        require(tableManager.isPlayerTurn(tableId, msg.sender), "Not your turn");
        require(tableManager.getPlayerTableStake(tableId, msg.sender) >= betAmount, "Bet exceeds table stake");
        require(betAmount >= tableManager.getTableBigBlind(tableId), "Bet below minimum");
        
        tableManager.updatePlayerBet(tableId, msg.sender, betAmount);
        
        // Move to next active player
        moveToNextPlayer(tableId);
        
        emit BetPlaced(tableId, msg.sender, betAmount);
    }

    function moveToNextPlayer(uint256 tableId) internal {
        tableManager.moveToNextPlayer(tableId);
        
        // Get current player for the event
        address currentPlayer = tableManager.getCurrentPlayer(tableId);
        if (currentPlayer != address(0)) {
            emit TurnStarted(tableId, currentPlayer);
        }

        if (!tableManager.hasNextActivePlayer(tableId) || tableManager.isRoundComplete(tableId)) {
            advanceGameState(tableId);
        }
    }

    function postBlinds(uint256 tableId) external onlyValidTable(tableId) {
        require(tableManager.getGameState(tableId) == uint8(GameState.PreFlop), "Not in PreFlop state");
        
        // Get players from table manager
        address[] memory players = tableManager.getTablePlayers(tableId);
        require(players.length >= 2, "Need at least 2 players");
        
        // Post small blind (Player 0)
        address smallBlindPlayer = players[0];
        uint256 smallBlindAmount = tableManager.getTableSmallBlind(tableId);
        require(tableManager.getPlayerTableStake(tableId, smallBlindPlayer) >= smallBlindAmount, "Small blind cannot cover bet");
        tableManager.updatePlayerBet(tableId, smallBlindPlayer, smallBlindAmount);
        
        // Post big blind (Player 1)
        address bigBlindPlayer = players[1];
        uint256 bigBlindAmount = tableManager.getTableBigBlind(tableId);
        require(tableManager.getPlayerTableStake(tableId, bigBlindPlayer) >= bigBlindAmount, "Big blind cannot cover bet");
        tableManager.updatePlayerBet(tableId, bigBlindPlayer, bigBlindAmount);
        
        emit BlindsPosted(tableId, smallBlindPlayer, bigBlindPlayer, smallBlindAmount, bigBlindAmount);
    }

    function advanceGameState(uint256 tableId) internal {
        // Require that all players have acted
        require(tableManager.isRoundComplete(tableId), "Not all players have acted");
        
        // Reset all hasActed flags and current bets for the new round
        tableManager.resetRound(tableId);
        
        uint8 currentState = tableManager.getGameState(tableId);
        if (currentState == uint8(GameState.PreFlop)) {
            tableManager.setGameState(tableId, GameState.Flop);
            // Deal flop cards
            uint8[] memory flopCards = new uint8[](3);
            flopCards[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop1"))) % 52 + 1);
            flopCards[1] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop2"))) % 52 + 1);
            flopCards[2] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop3"))) % 52 + 1);
            dealCommunityCards(tableId, flopCards);
        } else if (currentState == uint8(GameState.Flop)) {
            tableManager.setGameState(tableId, GameState.Turn);
            // Deal turn card
            uint8[] memory turnCard = new uint8[](1);
            turnCard[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "turn"))) % 52 + 1);
            dealCommunityCards(tableId, turnCard);
        } else if (currentState == uint8(GameState.Turn)) {
            tableManager.setGameState(tableId, GameState.River);
            // Deal river card
            uint8[] memory riverCard = new uint8[](1);
            riverCard[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "river"))) % 52 + 1);
            dealCommunityCards(tableId, riverCard);
        } else if (currentState == uint8(GameState.River)) {
            tableManager.setGameState(tableId, GameState.Showdown);
            determineWinner(tableId);
        }
    }

    function dealCommunityCards(uint256 tableId, uint8[] memory cards) internal {
        tableManager.addCommunityCards(tableId, cards);
        emit CommunityCardsDealt(tableId, cards);
    }

    function determineWinner(uint256 tableId) internal {
        // Find player with highest hand
        address winner;
        PokerHandEval.HandRank highestRank = PokerHandEval.HandRank.HighCard;
        uint256 highestScore = 0;
        
        address[] memory players = tableManager.getTablePlayers(tableId);
        for (uint i = 0; i < players.length; i++) {
            address playerAddr = players[i];
            if (tableManager.isPlayerActive(tableId, playerAddr)) {
                // Get player's cards and community cards
                uint8[] memory playerCards = tableManager.getPlayerCards(tableId, playerAddr);
                uint8[] memory communityCards = tableManager.getCommunityCards(tableId);
                uint8[] memory allCards = new uint8[](7);
                
                // Combine player cards and community cards
                allCards[0] = playerCards[0];
                allCards[1] = playerCards[1];
                for(uint j = 0; j < communityCards.length; j++) {
                    allCards[j + 2] = communityCards[j];
                }
                
                // Evaluate hand
                (PokerHandEval.HandRank rank, uint256 score) = handEvaluator.evaluateHand(allCards);
                
                // Update winner if this hand is better
                if (winner == address(0) || 
                    uint8(rank) > uint8(highestRank) || 
                    (uint8(rank) == uint8(highestRank) && score > highestScore)) {
                    winner = playerAddr;
                    highestRank = rank;
                    highestScore = score;
                }
            }
        }
        
        // Award pot to winner
        if (winner != address(0)) {
            uint256 potAmount = tableManager.getTablePot(tableId);
            tableManager.awardPotToPlayer(tableId, winner);
            
            // Emit events
            emit HandComplete(tableId, winner, potAmount);
            emit HandWinner(tableId, winner, highestRank, potAmount);
        }

        tableManager.setGameState(tableId, GameState.Complete);
        
        // Start new hand if enough players
        if (tableManager.getPlayerCount(tableId) >= 2) {
            startNewHand(tableId);
        } else {
            tableManager.setGameState(tableId, GameState.Waiting);
        }
    }

    function check(uint256 tableId) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        require(tableManager.isPlayerTurn(tableId, msg.sender), "Not your turn");
        require(tableManager.getPlayerCurrentBet(tableId, msg.sender) == tableManager.getTableCurrentBet(tableId), "Cannot check");
        
        tableManager.setPlayerHasActed(tableId, msg.sender, true);
        
        emit TurnEnded(tableId, msg.sender, "check");
        moveToNextPlayer(tableId);
    }

    function call(uint256 tableId) 
        external 
        onlyValidTable(tableId) 
        onlyTablePlayer(tableId) 
    {
        require(tableManager.isPlayerTurn(tableId, msg.sender), "Not your turn");
        
        uint256 callAmount = tableManager.getTableCurrentBet(tableId) - tableManager.getPlayerCurrentBet(tableId, msg.sender);
        require(tableManager.getPlayerTableStake(tableId, msg.sender) >= callAmount, "Insufficient funds");
        
        tableManager.updatePlayerBet(tableId, msg.sender, callAmount);
        tableManager.setPlayerHasActed(tableId, msg.sender, true);
        
        emit BetPlaced(tableId, msg.sender, callAmount);
        emit TurnEnded(tableId, msg.sender, "call");
        
        moveToNextPlayer(tableId);
    }

    function startFlop(uint256 tableId) external onlyValidTable(tableId) {
        require(tableManager.getGameState(tableId) == uint8(GameState.PreFlop), "Not in PreFlop state");
        require(tableManager.isRoundComplete(tableId), "Not all players have acted");
        
        // Deal flop cards
        uint8[] memory flopCards = new uint8[](3);
        flopCards[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop1"))) % 52 + 1);
        flopCards[1] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop2"))) % 52 + 1);
        flopCards[2] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "flop3"))) % 52 + 1);
        
        dealCommunityCards(tableId, flopCards);
        tableManager.setGameState(tableId, GameState.Flop);
    }

    function startTurn(uint256 tableId) external onlyValidTable(tableId) {
        require(tableManager.getGameState(tableId) == uint8(GameState.Flop), "Not in Flop state");
        require(tableManager.isRoundComplete(tableId), "Not all players have acted");

        // Deal turn card
        uint8[] memory turnCard = new uint8[](1);
        turnCard[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "turn"))) % 52 + 1);
        
        dealCommunityCards(tableId, turnCard);
        tableManager.setGameState(tableId, GameState.Turn);
    }

    function startRiver(uint256 tableId) external onlyValidTable(tableId) {
        require(tableManager.getGameState(tableId) == uint8(GameState.Turn), "Not in Turn state");
        require(tableManager.isRoundComplete(tableId), "Not all players have acted");

        // Deal river card
        uint8[] memory riverCard = new uint8[](1);
        riverCard[0] = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, tableId, "river"))) % 52 + 1);
        
        dealCommunityCards(tableId, riverCard);
        tableManager.setGameState(tableId, GameState.River);
    }

    function startShowdown(uint256 tableId) external onlyValidTable(tableId) {
        require(tableManager.getGameState(tableId) == uint8(GameState.River), "Invalid game state");
        require(tableManager.isRoundComplete(tableId), "Not all players have acted");

        tableManager.setGameState(tableId, GameState.Showdown);
        determineWinner(tableId);
    }
}
}
