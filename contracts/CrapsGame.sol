// SPDX-License-Identifier: MIT 
// Solidity Contract for a Craps Game
// This contract will allow users to place various types of bets typically found in a Craps game.
// The outcome of each roll is to be determined off-chain.

pragma solidity ^0.8.0;

contract CrapsGame {
    address public owner;
    enum BetType { Pass, DontPass, Come, DontCome, Field, AnySeven, AnyCraps, Hardway } // Bet types in Craps

    struct Bet {
        address player;
        BetType betType;
        uint256 amount;
    }

    Bet[] public bets;
    mapping(address => uint256) public playerBalances;

    // Constructor to set contract owner
    constructor() {
        owner = msg.sender;
    }

    // Modifier to restrict function calls to only the owner
    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    // Function to fund the contract (used for payouts)
    function fundContract() external payable onlyOwner {
        require(msg.value > 0, "Must send some Ether to fund the contract.");
    }

    // Function for players to place bets
    function placeBet(BetType betType) external payable {
        require(msg.value > 0, "Must place a bet greater than 0.");
        bets.push(Bet({
            player: msg.sender,
            betType: betType,
            amount: msg.value
        }));
    }

    // Function to resolve a roll (to be called off-chain)
    function resolveRoll(uint8 rollOutcome) external onlyOwner {
        require(rollOutcome >= 2 && rollOutcome <= 12, "Invalid roll outcome.");
        for (uint256 i = 0; i < bets.length; i++) {
            Bet storage bet = bets[i];
            bool won = false;

            if (bet.betType == BetType.Pass && (rollOutcome == 7 || rollOutcome == 11)) {
                won = true;
            } else if (bet.betType == BetType.DontPass && (rollOutcome == 2 || rollOutcome == 3 || rollOutcome == 12)) {
                won = true;
            }
            // Additional conditions for other bet types go here...

            if (won) {
                playerBalances[bet.player] += bet.amount * 2; // Winner gets double their bet
            }
        }
        // Clear bets after resolving
        delete bets;
    }

    // Function to withdraw winnings
    function withdrawWinnings() external {
        uint256 balance = playerBalances[msg.sender];
        require(balance > 0, "No winnings to withdraw.");
        playerBalances[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed.");
    }
}