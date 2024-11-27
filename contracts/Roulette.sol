// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;
import "./HouseTreasury.sol";

contract Roulette {
    address public owner;
    uint256 public minBetAmount;
    HouseTreasury public treasury;

    enum BetType { 
        Straight,    // Single number (35:1)
        Split,       // Two numbers (17:1)
        Street,      // Three numbers (11:1)
        Corner,      // Four numbers (8:1)
        Line,        // Six numbers (5:1)
        Column,      // Twelve numbers (2:1)
        Dozen,       // Twelve numbers (2:1)
        Red,         // Red numbers (1:1)
        Black,       // Black numbers (1:1)
        Even,        // Even numbers (1:1)
        Odd,         // Odd numbers (1:1)
        Low,         // 1-18 (1:1)
        High        // 19-36 (1:1)
    }

    struct Bet {
        address player;
        BetType betType;
        uint256 amount;
        uint8[] numbers;    // Numbers covered by the bet
    }

    mapping(address => Bet[]) public playerBets;
    uint8[] public redNumbers = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];

    // Add a state variable to track players with active bets
    address[] private activePlayers;

    event BetPlaced(address indexed player, BetType betType, uint256 amount, uint8[] numbers);
    event SpinResult(uint8 number);
    event Payout(address indexed player, uint256 amount);

    constructor(uint256 _minBetAmount, address _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    function placeBet(BetType betType, uint8[] calldata numbers) external payable {
        require(msg.value >= minBetAmount, "Bet amount is below minimum required.");
        require(isValidBet(betType, numbers), "Invalid bet configuration.");

        // Add player to activePlayers if not already present
        if (playerBets[msg.sender].length == 0) {
            activePlayers.push(msg.sender);
        }

        playerBets[msg.sender].push(Bet({
            player: msg.sender,
            betType: betType,
            amount: msg.value,
            numbers: numbers
        }));

        emit BetPlaced(msg.sender, betType, msg.value, numbers);
    }

    function spin(uint8 result) external onlyOwner {
        require(result <= 36, "Invalid roulette number.");
        emit SpinResult(result);

        // Process bets for each player
        for (uint256 p = 0; p < activePlayers.length; p++) {
            address player = activePlayers[p];
            Bet[] storage playerBetList = playerBets[player];

            // Process all bets for this player
            for (uint256 i = 0; i < playerBetList.length; i++) {
                Bet memory bet = playerBetList[i];
                uint256 winnings = calculateWinnings(bet, result);
                
                if (winnings > 0) {
                    treasury.payout(bet.player, winnings);
                    emit Payout(bet.player, winnings);
                }
            }

            // Clear all bets for this player
            delete playerBets[player];
        }

        // Clear the active players list
        delete activePlayers;
    }

    // Modify the getActivePlayers function to use the activePlayers list
    function getActivePlayers() internal view returns (address[] memory) {
        return activePlayers;
    }

    function calculateWinnings(Bet memory bet, uint8 result) internal view returns (uint256) {
        if (!isWinningBet(bet, result)) return 0;

        uint256 multiplier = getMultiplier(bet.betType);
        return bet.amount * multiplier;
    }

    function isWinningBet(Bet memory bet, uint8 result) internal view returns (bool) {
        if (bet.betType == BetType.Straight) {
            return bet.numbers[0] == result;
        } else if (bet.betType == BetType.Red) {
            return isRed(result);
        } else if (bet.betType == BetType.Black) {
            return !isRed(result) && result != 0;
        } else if (bet.betType == BetType.Even) {
            return result != 0 && result % 2 == 0;
        } else if (bet.betType == BetType.Odd) {
            return result % 2 == 1;
        } else if (bet.betType == BetType.Low) {
            return result >= 1 && result <= 18;
        } else if (bet.betType == BetType.High) {
            return result >= 19 && result <= 36;
        }
        
        // For other bet types, check if result is in the bet numbers array
        for (uint256 i = 0; i < bet.numbers.length; i++) {
            if (bet.numbers[i] == result) return true;
        }
        return false;
    }

    function getMultiplier(BetType betType) internal pure returns (uint256) {
        if (betType == BetType.Straight) return 36;
        if (betType == BetType.Split) return 18;
        if (betType == BetType.Street) return 12;
        if (betType == BetType.Corner) return 9;
        if (betType == BetType.Line) return 6;
        if (betType == BetType.Column || betType == BetType.Dozen) return 3;
        return 2; // For all even money bets (Red/Black, Even/Odd, Low/High)
    }

    function isValidBet(BetType betType, uint8[] memory numbers) internal pure returns (bool) {
        if (betType == BetType.Straight) return numbers.length == 1 && numbers[0] <= 36;
        if (betType == BetType.Split) return numbers.length == 2;
        if (betType == BetType.Street) return numbers.length == 3;
        if (betType == BetType.Corner) return numbers.length == 4;
        if (betType == BetType.Line) return numbers.length == 6;
        if (betType == BetType.Column || betType == BetType.Dozen) return numbers.length == 12;
        return numbers.length == 0; // For Red/Black, Even/Odd, Low/High
    }

    function isRed(uint8 number) internal view returns (bool) {
        for (uint256 i = 0; i < redNumbers.length; i++) {
            if (redNumbers[i] == number) return true;
        }
        return false;
    }

    function getPlayerBets(address player) external view returns (Bet[] memory) {
        return playerBets[player];
    }

    // Allow contract to receive funds
    receive() external payable {}
}