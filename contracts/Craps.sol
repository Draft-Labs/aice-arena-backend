// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./HouseTreasury.sol";

contract Craps is ReentrancyGuard {
    address public owner;
    uint256 public minBetAmount;
    HouseTreasury public treasury;
    
    enum BetType { Pass, DontPass, Come, DontCome, Field, AnySeven, AnyCraps, Hardway }
    enum GamePhase { Off, Come }

    struct Bet {
        address player;
        BetType betType;
        uint256 amount;
        bool resolved;
    }

    mapping(address => mapping(BetType => Bet)) public playerBets;
    address[] private activePlayers;
    GamePhase public currentPhase;
    uint8 public point;

    mapping(address => uint256) private pendingWithdrawals;
    mapping(address => bool) private activeGames;
    bool private resolving;

    bool private paused;
    uint256 private maxWithdrawalAmount = 10 ether;
    mapping(address => uint256) private lastActionTime;
    uint256 private actionCooldown;

    event BetPlaced(address indexed player, BetType betType, uint256 amount);
    event GameResolved(address indexed player, uint256 winnings);
    event PointEstablished(uint8 point);
    event RollResult(uint8 roll);
    event ContractPaused();
    event ContractUnpaused();
    event BetResolved(address indexed player, uint256 amount);

    constructor(uint256 _minBetAmount, address payable _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
        currentPhase = GamePhase.Off;
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

    function pause() external onlyOwner {
        paused = true;
        emit ContractPaused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit ContractUnpaused();
    }

    function placeBet(BetType betType) external payable nonReentrant whenNotPaused rateLimited {
        require(msg.value >= minBetAmount, "Bet amount is below minimum required.");
        require(playerBets[msg.sender][betType].amount == 0, "Player already has an active bet of this type.");

        playerBets[msg.sender][betType] = Bet({
            player: msg.sender,
            betType: betType,
            amount: msg.value,
            resolved: false
        });

        if (!isActivePlayer(msg.sender)) {
            activePlayers.push(msg.sender);
        }
        
        emit BetPlaced(msg.sender, betType, msg.value);
    }

    function resolveRoll(uint8 rollOutcome) external onlyOwner nonReentrant notResolving {
        resolving = true;
        require(rollOutcome >= 2 && rollOutcome <= 12, "Invalid roll outcome.");
        emit RollResult(rollOutcome);

        // Create temporary storage for winnings
        address[] memory winners = new address[](activePlayers.length);
        uint256[] memory winningAmounts = new uint256[](activePlayers.length);
        uint256 winnerCount = 0;

        // First, calculate all winnings and update state
        for (uint256 i = 0; i < activePlayers.length; i++) {
            address player = activePlayers[i];
            
            for (uint8 j = 0; j < 8; j++) {
                BetType betType = BetType(j);
                Bet storage bet = playerBets[player][betType];
                
                if (bet.amount > 0 && !bet.resolved) {
                    uint256 winnings = calculateWinnings(bet, rollOutcome);
                    if (winnings > 0) {
                        winners[winnerCount] = player;
                        winningAmounts[winnerCount] = winnings;
                        winnerCount++;
                    }
                    // Mark bet as resolved
                    bet.resolved = true;
                }
            }
        }

        // Update game state
        updateGameState(rollOutcome);
        
        // Clear resolved bets
        clearResolvedBets();

        // Finally, process all payouts
        for (uint256 i = 0; i < winnerCount; i++) {
            treasury.payout(winners[i], winningAmounts[i]);
            emit GameResolved(winners[i], winningAmounts[i]);
        }
        resolving = false;
    }

    function calculateWinnings(Bet memory bet, uint8 roll) internal pure returns (uint256) {
        // Add your winning calculation logic here based on bet type and roll
        // This is a simplified example
        if (bet.betType == BetType.Pass && (roll == 7 || roll == 11)) {
            return bet.amount * 2;
        }
        // Add other bet type calculations
        return 0;
    }

    function updateGameState(uint8 roll) internal {
        if (currentPhase == GamePhase.Off) {
            if (roll == 4 || roll == 5 || roll == 6 || roll == 8 || roll == 9 || roll == 10) {
                point = roll;
                currentPhase = GamePhase.Come;
                emit PointEstablished(roll);
            }
        } else if (currentPhase == GamePhase.Come && (roll == 7 || roll == point)) {
            currentPhase = GamePhase.Off;
            point = 0;
        }
    }

    function clearResolvedBets() internal {
        address[] memory remainingPlayers = new address[](activePlayers.length);
        uint256 remainingCount = 0;

        for (uint256 i = 0; i < activePlayers.length; i++) {
            address player = activePlayers[i];
            bool hasActiveBets = false;
            
            for (uint8 j = 0; j < 8; j++) {
                BetType betType = BetType(j);
                Bet storage bet = playerBets[player][betType];
                if (bet.amount > 0) {
                    if (bet.resolved) {
                        bet.amount = 0;
                        bet.resolved = true;
                    } else {
                        hasActiveBets = true;
                    }
                }
            }
            
            if (hasActiveBets) {
                remainingPlayers[remainingCount] = player;
                remainingCount++;
            }
        }

        delete activePlayers;
        for (uint256 i = 0; i < remainingCount; i++) {
            activePlayers.push(remainingPlayers[i]);
        }
    }

    function isActivePlayer(address player) internal view returns (bool) {
        for (uint256 i = 0; i < activePlayers.length; i++) {
            if (activePlayers[i] == player) return true;
        }
        return false;
    }

    function removeActivePlayer(uint256 index) internal {
        require(index < activePlayers.length);
        activePlayers[index] = activePlayers[activePlayers.length - 1];
        activePlayers.pop();
    }

    function getActivePlayers() external view returns (address[] memory) {
        return activePlayers;
    }

    function withdrawWinnings() external nonReentrant circuitBreaker(pendingWithdrawals[msg.sender]) {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No winnings to withdraw");

        pendingWithdrawals[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function setActionCooldown(uint256 _cooldown) external onlyOwner {
        actionCooldown = _cooldown;
    }
}