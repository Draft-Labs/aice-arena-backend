// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPokerBase.sol";

interface IPokerGame {
    // Game actions
    function placeBet(uint256 tableId, uint256 amount) external;
    function fold(uint256 tableId) external;
    function call(uint256 tableId) external;
    function raise(uint256 tableId, uint256 amount) external;
    function check(uint256 tableId) external;

    // Game state transitions
    function startFlop(uint256 tableId) external;
    function startTurn(uint256 tableId) external;
    function startRiver(uint256 tableId) external;
    function startShowdown(uint256 tableId) external;
    function startNewHand(uint256 tableId) external;

    // Game state queries
    function isPlayerTurn(uint256 tableId, address player) external view returns (bool);
    function getCurrentBet(uint256 tableId) external view returns (uint256);
    function getPot(uint256 tableId) external view returns (uint256);
    function getGameState(uint256 tableId) external view returns (IPokerBase.GameState);
    function getCurrentPosition(uint256 tableId) external view returns (uint256);
    function getDealerPosition(uint256 tableId) external view returns (uint256);
    function hasPlayerActed(uint256 tableId, uint256 position) external view returns (bool);
    function isRoundComplete(uint256 tableId) external view returns (bool);
} 