// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./HouseTreasury.sol";

contract Roulette is ReentrancyGuard {
    address public owner;
    uint256 public minBetAmount;
    HouseTreasury public treasury;

    struct Bet {
        address player;
        uint256 amount;
        uint8 number;    // The number being bet on
    }

    // Create temporary storage for winnings
    struct WinningInfo {
        address player;
        uint256 amount;
    }

    mapping(address => Bet[]) public playerBets;

    // Add a state variable to track players with active bets
    address[] private activePlayers;

    mapping(address => uint256) private pendingWithdrawals;
    mapping(address => bool) private activeGames;
    bool private resolving;

    event BetPlaced(address indexed player, uint256 amount, uint8 number);
    event SpinResult(uint8 number);
    event Payout(address indexed player, uint256 amount);
    event ContractPaused();
    event ContractUnpaused();
    event BetResolved(address indexed player, uint256 amount);
    event GameResult(uint8 result, uint256 payout, bool won);

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

    function placeBet(uint8[] calldata numbers) external payable nonReentrant whenNotPaused {
        require(msg.value >= minBetAmount * numbers.length, "Bet amount below minimum");
        require(numbers.length > 0, "Must bet on at least one number");
        
        uint256 individualBetAmount = msg.value / numbers.length;
        require(individualBetAmount >= minBetAmount, "Individual bet amount below minimum");
        
        // Forward the bet amount to the treasury
        (bool success, ) = address(treasury).call{value: msg.value}("");
        require(success, "Transfer to treasury failed");

        // Add player to activePlayers if not already present
        if (playerBets[msg.sender].length == 0) {
            activePlayers.push(msg.sender);
        }
        
        // Place individual bets for each number
        for (uint256 i = 0; i < numbers.length; i++) {
            require(numbers[i] <= 36, "Invalid roulette number");
            
            playerBets[msg.sender].push(Bet({
                player: msg.sender,
                amount: individualBetAmount,
                number: numbers[i]
            }));
            
            emit BetPlaced(msg.sender, individualBetAmount, numbers[i]);
        }
    }

    function spin(uint8 result) external onlyOwner nonReentrant notResolving {
        resolving = true;
        require(result <= 36, "Invalid roulette number.");
        emit SpinResult(result);

        WinningInfo[] memory winnings = new WinningInfo[](activePlayers.length * 10); // Assuming max 10 bets per player
        uint256 winningCount = 0;

        // Calculate all winnings and update state
        for (uint256 p = 0; p < activePlayers.length; p++) {
            address player = activePlayers[p];
            Bet[] storage playerBetList = playerBets[player];

            for (uint256 i = 0; i < playerBetList.length; i++) {
                Bet memory bet = playerBetList[i];
                
                if (bet.number == result) {
                    // 35:1 payout for winning straight-up bets
                    uint256 winningAmount = bet.amount * 36; // includes original bet
                    winnings[winningCount] = WinningInfo({
                        player: bet.player,
                        amount: winningAmount
                    });
                    winningCount++;
                    emit GameResult(result, winningAmount, true);
                } else {
                    emit GameResult(result, 0, false);
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