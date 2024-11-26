// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

contract Blackjack {
    address public owner;
    uint256 public minBetAmount;
    mapping(address => uint256) public playerBets;

    // Constructor to set the contract owner and the minimum bet amount
    constructor(uint256 _minBetAmount) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
    }

    // Modifier to restrict functions to only the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    // Function to fund the contract (owner funds it for payouts)
    function fundContract() external payable onlyOwner {
        require(msg.value > 0, "Must send some Ether to fund the contract.");
    }

    // Function to place a bet
    function placeBet() external payable {
        require(msg.value >= minBetAmount, "Bet amount is below the minimum required.");
        require(playerBets[msg.sender] == 0, "You have an existing bet.");

        playerBets[msg.sender] = msg.value;
    }

    // Function to clear bet after game is resolved (called off-chain after the result is computed)
    function clearBet(address player) external onlyOwner {
        playerBets[player] = 0;
    }

    // Function to payout winnings
    function payoutWinnings(address winner, uint256 amount) external onlyOwner {
        require(playerBets[winner] > 0, "Player does not have an active bet.");
        require(amount <= address(this).balance, "Not enough balance in contract to payout.");
        
        playerBets[winner] = 0;
        (bool success, ) = winner.call{value: amount}("");
        require(success, "Transfer failed.");
    }
}