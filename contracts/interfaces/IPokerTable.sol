// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPokerBase.sol";

interface IPokerTable {
    // Table management
    function createTable(
        uint256 minBuyIn,
        uint256 maxBuyIn,
        uint256 smallBlind,
        uint256 bigBlind,
        uint256 minBet,
        uint256 maxBet
    ) external returns (uint256 tableId);

    function joinTable(uint256 tableId, uint256 buyInAmount) external;
    function leaveTable(uint256 tableId) external;
    function sitOut(uint256 tableId) external;
    function sitIn(uint256 tableId) external;

    // Table queries
    function getTableInfo(uint256 tableId) external view returns (IPokerBase.Table memory);
    function getPlayerInfo(uint256 tableId, address player) external view returns (IPokerBase.Player memory);
    function getTablePlayers(uint256 tableId) external view returns (address[] memory);
    function getActiveTables() external view returns (uint256[] memory);
    function getMaxTables() external view returns (uint256);
    function getMaxPlayersPerTable() external view returns (uint256);
    function isTableActive(uint256 tableId) external view returns (bool);
    function getPlayerCount(uint256 tableId) external view returns (uint256);
    function isPlayerAtTable(uint256 tableId, address player) external view returns (bool);

    // Table configuration
    function updateTableConfig(
        uint256 tableId,
        uint256 minBet,
        uint256 maxBet
    ) external;
} 