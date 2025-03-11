// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import "./IPokerTables.sol";

interface IPokerFunctionality {
    // External gameplay functions
    function placeBet(uint256 tableId, uint256 betAmount) external;
    function fold(uint256 tableId) external;
    function check(uint256 tableId) external;
    function call(uint256 tableId) external;
    function raise(uint256 tableId, uint256 amount) external;

    // Admin functions to control game flow
    function startNewHand(uint256 tableId) external;
    function postBlinds(uint256 tableId) external;
    function startFlop(uint256 tableId) external;
    function startTurn(uint256 tableId) external;
    function startRiver(uint256 tableId) external;
    function startShowdown(uint256 tableId) external;

    // View functions
    function getPlayerCards(uint256 tableId, address player) external view returns (uint8[] memory);
    function getCommunityCards(uint256 tableId) external view returns (uint8[] memory);
} 