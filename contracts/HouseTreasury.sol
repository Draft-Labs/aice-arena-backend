// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract HouseTreasury {
    address public owner;
    mapping(address => bool) public authorizedGames;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    modifier onlyAuthorizedGame() {
        require(authorizedGames[msg.sender], "Only authorized games can call this function.");
        _;
    }

    function authorizeGame(address gameContract) external onlyOwner {
        authorizedGames[gameContract] = true;
    }

    function deauthorizeGame(address gameContract) external onlyOwner {
        authorizedGames[gameContract] = false;
    }

    function fundTreasury() external payable onlyOwner {
        require(msg.value > 0, "Must send some Ether to fund the treasury.");
    }

    function getTreasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function payout(address winner, uint256 amount) external onlyAuthorizedGame {
        require(amount <= address(this).balance, "Not enough balance in treasury to payout.");
        (bool success, ) = winner.call{value: amount}("");
        require(success, "Transfer failed.");
    }
}