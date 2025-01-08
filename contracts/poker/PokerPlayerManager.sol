// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IPokerTable.sol";

/**
 * @title PokerPlayerManager
 * @dev Contract for managing poker player functionality
 */
contract PokerPlayerManager is Ownable {
    IPokerTable public pokerTable;

    // Events
    event PlayerJoined(uint256 indexed tableId, address indexed player, uint256 buyIn);
    event PlayerLeft(uint256 indexed tableId, address indexed player, uint256 amountReturned);
    event PlayerKicked(uint256 indexed tableId, address indexed player, uint256 amountReturned);
    event PlayerTimeout(uint256 indexed tableId, address indexed player);

    // Error messages
    error InvalidBuyIn();
    error TableFull();
    error PlayerNotFound();
    error PlayerAlreadyJoined();
    error InsufficientBalance();
    error PlayerInGame();
    error NotAuthorized();

    constructor(address _pokerTableAddress) Ownable(msg.sender) {
        pokerTable = IPokerTable(_pokerTableAddress);
    }

    /**
     * @dev Updates the PokerTable contract address
     */
    function setPokerTable(address _pokerTableAddress) external onlyOwner {
        require(_pokerTableAddress != address(0), "Invalid address");
        pokerTable = IPokerTable(_pokerTableAddress);
    }

    /**
     * @dev Allows a player to join a table
     */
    function joinTable(uint256 tableId, uint256 buyIn) external payable {
        // Get table info
        (
            uint256 minBuyIn,
            uint256 maxBuyIn,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = pokerTable.getTableInfo(tableId);

        // Validate buy-in amount
        if (buyIn < minBuyIn || buyIn > maxBuyIn) revert InvalidBuyIn();
        if (msg.value != buyIn) revert InvalidBuyIn();

        // Check if table is full
        address[] memory players = pokerTable.getTablePlayers(tableId);
        if (players.length >= 9) revert TableFull();

        // Check if player is already at the table
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == msg.sender) revert PlayerAlreadyJoined();
        }

        // Add player to table
        bool success = pokerTable.addPlayer(tableId, msg.sender, buyIn);
        if (!success) revert PlayerNotFound();

        emit PlayerJoined(tableId, msg.sender, buyIn);
    }

    /**
     * @dev Allows a player to leave a table
     */
    function leaveTable(uint256 tableId) external {
        // Get player info
        (uint256 tableStake, , bool isActive, , bool inHand) = pokerTable.getPlayerInfo(tableId, msg.sender);

        // Check if player can leave
        if (inHand) revert PlayerInGame();
        if (!isActive) revert PlayerNotFound();

        // Remove player from table
        bool success = pokerTable.removePlayer(tableId, msg.sender);
        if (!success) revert PlayerNotFound();

        // Return player's stake
        (bool sent, ) = payable(msg.sender).call{value: tableStake}("");
        require(sent, "Failed to send Ether");

        emit PlayerLeft(tableId, msg.sender, tableStake);
    }

    /**
     * @dev Allows the owner to kick a player from a table
     */
    function kickPlayer(uint256 tableId, address player) external onlyOwner {
        // Get player info
        (uint256 tableStake, , bool isActive, , bool inHand) = pokerTable.getPlayerInfo(tableId, player);

        // Check if player can be kicked
        if (!isActive) revert PlayerNotFound();
        if (inHand) revert PlayerInGame();

        // Remove player from table
        bool success = pokerTable.removePlayer(tableId, player);
        if (!success) revert PlayerNotFound();

        // Return player's stake
        (bool sent, ) = payable(player).call{value: tableStake}("");
        require(sent, "Failed to send Ether");

        emit PlayerKicked(tableId, player, tableStake);
    }

    /**
     * @dev Handles player timeout
     */
    function handleTimeout(uint256 tableId, address player) external {
        // Only the poker table contract can call this
        if (msg.sender != address(pokerTable)) revert NotAuthorized();

        // Get player info
        (uint256 tableStake, , bool isActive, , bool inHand) = pokerTable.getPlayerInfo(tableId, player);

        // Check if player is active
        if (!isActive) revert PlayerNotFound();

        // If player is in hand, they forfeit their current bet
        if (inHand) {
            // Logic to handle forfeiting current bet would go here
            // This would need to be coordinated with the PokerBetting contract
        }

        // Remove player from table
        bool success = pokerTable.removePlayer(tableId, player);
        if (!success) revert PlayerNotFound();

        // Return remaining stake to player
        (bool sent, ) = payable(player).call{value: tableStake}("");
        require(sent, "Failed to send Ether");

        emit PlayerTimeout(tableId, player);
    }

    /**
     * @dev Allows a player to add more chips to their stack
     */
    function addChips(uint256 tableId, uint256 amount) external payable {
        // Get table info
        (
            ,
            uint256 maxBuyIn,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = pokerTable.getTableInfo(tableId);

        // Get player info
        (uint256 currentStake, , bool isActive, , bool inHand) = pokerTable.getPlayerInfo(tableId, msg.sender);

        // Validate
        if (!isActive) revert PlayerNotFound();
        if (inHand) revert PlayerInGame();
        if (msg.value != amount) revert InvalidBuyIn();
        if (currentStake + amount > maxBuyIn) revert InvalidBuyIn();

        // Update player's stake
        bool success = pokerTable.updatePlayerStake(tableId, msg.sender, currentStake + amount);
        if (!success) revert PlayerNotFound();
    }

    /**
     * @dev Allows a player to remove chips from their stack
     */
    function removeChips(uint256 tableId, uint256 amount) external {
        // Get table info
        (
            uint256 minBuyIn,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = pokerTable.getTableInfo(tableId);

        // Get player info
        (uint256 currentStake, , bool isActive, , bool inHand) = pokerTable.getPlayerInfo(tableId, msg.sender);

        // Validate
        if (!isActive) revert PlayerNotFound();
        if (inHand) revert PlayerInGame();
        if (amount > currentStake) revert InsufficientBalance();
        if (currentStake - amount < minBuyIn) revert InvalidBuyIn();

        // Update player's stake
        bool success = pokerTable.updatePlayerStake(tableId, msg.sender, currentStake - amount);
        if (!success) revert PlayerNotFound();

        // Return chips to player
        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @dev Allows the contract to receive ETH
     */
    receive() external payable {}

    /**
     * @dev Fallback function
     */
    fallback() external payable {}
} 