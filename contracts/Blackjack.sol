// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;
import "./HouseTreasury.sol";

contract Blackjack {
    address public owner;
    uint256 public minBetAmount;
    HouseTreasury public treasury;
    mapping(address => uint256) public playerBets;

    // Constructor to set the contract owner and the minimum bet amount
    constructor(uint256 _minBetAmount, address _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
    }

    // Modifier to restrict functions to only the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    // Function to place a bet
    function placeBet() external payable {
        require(msg.value >= minBetAmount, "Bet amount is below the minimum required.");
        require(playerBets[msg.sender] == 0, "Player already has an active bet.");

        playerBets[msg.sender] = msg.value;
    }

    // Function to clear bet after game is resolved (called off-chain after the result is computed)
    function clearBet(address player) external onlyOwner {
        playerBets[player] = 0;
    }

    // Updated payout function
    function payoutWinnings(address winner, uint256 amount) external onlyOwner {
        require(playerBets[winner] > 0, "Player does not have an active bet.");
        playerBets[winner] = 0;
        treasury.payout(winner, amount);
    }
}