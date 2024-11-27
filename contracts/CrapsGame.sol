// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;
import "./HouseTreasury.sol";

contract CrapsGame {
    address public owner;
    uint256 public minBetAmount;
    HouseTreasury public treasury;
    enum BetType { Pass, DontPass, Come, DontCome, Field, AnySeven, AnyCraps, Hardway }

    struct Bet {
        address player;
        BetType betType;
        uint256 amount;
    }

    Bet[] public bets;
    mapping(address => uint256) public playerBalances;
    mapping(address => mapping(BetType => uint256)) public playerBets;

    constructor(uint256 _minBetAmount, address _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    function placeBet(BetType betType) external payable {
        require(msg.value >= minBetAmount, "Bet amount is below minimum required.");
        require(playerBets[msg.sender][betType] == 0, "Player already has an active bet of this type.");

        playerBets[msg.sender][betType] = msg.value;
        bets.push(Bet({
            player: msg.sender,
            betType: betType,
            amount: msg.value
        }));
    }

    function resolveRoll(uint8 rollOutcome) external onlyOwner {
        require(rollOutcome >= 2 && rollOutcome <= 12, "Invalid roll outcome.");
        
        for (uint256 i = 0; i < bets.length; i++) {
            Bet storage bet = bets[i];
            bool won = false;
            uint256 winnings = 0;

            if (bet.betType == BetType.Pass && (rollOutcome == 7 || rollOutcome == 11)) {
                won = true;
                winnings = bet.amount * 2;
            } else if (bet.betType == BetType.DontPass && (rollOutcome == 2 || rollOutcome == 3 || rollOutcome == 12)) {
                won = true;
                winnings = bet.amount * 2;
            }

            if (won) {
                treasury.payout(bet.player, winnings);
            }
            
            // Clear the bet regardless of outcome
            playerBets[bet.player][bet.betType] = 0;
        }
        delete bets;
    }

    function getBetsLength() external view returns (uint256) {
        return bets.length;
    }

    function getPlayerBet(address player, BetType betType) external view returns (uint256) {
        return playerBets[player][betType];
    }
}