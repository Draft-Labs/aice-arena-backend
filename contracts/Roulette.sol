// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./HouseTreasury.sol";

contract Roulette is ReentrancyGuard {
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

    // Create temporary storage for winnings
    struct WinningInfo {
        address player;
        uint256 amount;
    }

    mapping(address => Bet[]) public playerBets;
    uint8[] public redNumbers = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];

    // Add a state variable to track players with active bets
    address[] private activePlayers;

    mapping(address => uint256) private pendingWithdrawals;
    mapping(address => bool) private activeGames;
    bool private resolving;

    event BetPlaced(address indexed player, BetType betType, uint256 amount, uint8[] numbers);
    event SpinResult(uint8 number);
    event Payout(address indexed player, uint256 amount);
    event ContractPaused();
    event ContractUnpaused();
    event BetResolved(address indexed player, uint256 amount);

    bool private paused;
    uint256 private maxWithdrawalAmount = 10 ether;
    mapping(address => uint256) private lastActionTime;
    uint256 private actionCooldown;

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier rateLimited() {
        require(block.timestamp >= lastActionTime[msg.sender] + actionCooldown, "Action rate limited");
        _;
        lastActionTime[msg.sender] = block.timestamp;
    }

    modifier circuitBreaker(uint256 amount) {
        require(amount <= maxWithdrawalAmount, "Withdrawal amount exceeds limit");
        _;
    }

    constructor(uint256 _minBetAmount, address payable _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(payable(_treasuryAddress));
        actionCooldown = 1 minutes;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    modifier notResolving() {
        require(!resolving, "Resolution in progress");
        _;
    }

    function placeBet(BetType betType, uint8[] calldata numbers) external nonReentrant whenNotPaused rateLimited {
        require(treasury.canPlaceBet(msg.sender, minBetAmount), "Insufficient balance or no active account");
        require(isValidBet(betType, numbers), "Invalid bet configuration.");

        // Process the bet amount from their treasury balance
        treasury.processBetLoss(msg.sender, minBetAmount);

        // Add player to activePlayers if not already present
        if (playerBets[msg.sender].length == 0) {
            activePlayers.push(msg.sender);
        }

        playerBets[msg.sender].push(Bet({
            player: msg.sender,
            betType: betType,
            amount: minBetAmount,
            numbers: numbers
        }));

        emit BetPlaced(msg.sender, betType, minBetAmount, numbers);
    }

    function spin(uint8 result) external onlyOwner nonReentrant notResolving {
        resolving = true;
        require(result <= 36, "Invalid roulette number.");
        emit SpinResult(result);

        WinningInfo[] memory winnings = new WinningInfo[](activePlayers.length * 10); // Assuming max 10 bets per player
        uint256 winningCount = 0;

        // First calculate all winnings and update state
        for (uint256 p = 0; p < activePlayers.length; p++) {
            address player = activePlayers[p];
            Bet[] storage playerBetList = playerBets[player];

            for (uint256 i = 0; i < playerBetList.length; i++) {
                Bet memory bet = playerBetList[i];
                uint256 winningAmount = calculateWinnings(bet, result);
                
                if (winningAmount > 0) {
                    winnings[winningCount] = WinningInfo({
                        player: bet.player,
                        amount: winningAmount
                    });
                    winningCount++;
                }
            }
            
            // Clear player's bets
            delete playerBets[player];
        }

        // Clear the active players list
        delete activePlayers;

        // Process all payouts through treasury
        for (uint256 i = 0; i < winningCount; i++) {
            treasury.processBetWin(winnings[i].player, winnings[i].amount);
            emit Payout(winnings[i].player, winnings[i].amount);
        }
        resolving = false;
    }

    // Modify the getActivePlayers function to use the activePlayers list
    function getActivePlayers() internal view returns (address[] memory) {
        return activePlayers;
    }

    function calculateWinnings(Bet memory bet, uint8 result) internal pure returns (uint256) {
        if (bet.betType == BetType.Straight && bet.numbers[0] == result) {
            return bet.amount * 36;
        }
        // Add other bet type calculations
        return 0;
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

    function pause() external onlyOwner {
        paused = true;
        emit ContractPaused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit ContractUnpaused();
    }

    // Add function to set cooldown (for testing)
    function setActionCooldown(uint256 _cooldown) external onlyOwner {
        actionCooldown = _cooldown;
    }
}