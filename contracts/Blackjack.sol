// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;
import "./HouseTreasury.sol";

contract Blackjack {
    address public owner;
    uint256 public minBetAmount;
    HouseTreasury public treasury;
    
    struct PlayerHand {
        uint256 bet;
        uint8[] cards;
        bool resolved;
    }
    
    mapping(address => PlayerHand) public playerHands;
    address[] private activePlayers;

    event BetPlaced(address indexed player, uint256 amount);
    event GameResolved(address indexed player, uint256 winnings);
    event CardDealt(address indexed player, uint8 card);

    constructor(uint256 _minBetAmount, address _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    function placeBet() external payable {
        require(msg.value >= minBetAmount, "Bet amount is below the minimum required.");
        require(playerHands[msg.sender].bet == 0, "Player already has an active bet.");

        playerHands[msg.sender] = PlayerHand({
            bet: msg.value,
            cards: new uint8[](0),
            resolved: false
        });
        activePlayers.push(msg.sender);
        
        emit BetPlaced(msg.sender, msg.value);
    }

    // Function to resolve all active games and process payouts
    function resolveGames(address[] calldata winners, uint8[] calldata multipliers) external onlyOwner {
        require(winners.length == multipliers.length, "Arrays length mismatch");
        
        for (uint256 i = 0; i < winners.length; i++) {
            address player = winners[i];
            require(playerHands[player].bet > 0, "No active bet for player");
            require(!playerHands[player].resolved, "Game already resolved");
            
            uint256 winnings = playerHands[player].bet * multipliers[i];
            if (winnings > 0) {
                treasury.payout(player, winnings);
                emit GameResolved(player, winnings);
            }
            
            playerHands[player].resolved = true;
        }
        
        // Clear all active games
        for (uint256 i = 0; i < activePlayers.length; i++) {
            delete playerHands[activePlayers[i]];
        }
        delete activePlayers;
    }

    function getActivePlayers() external view returns (address[] memory) {
        return activePlayers;
    }
}