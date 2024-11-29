// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./HouseTreasury.sol";

contract Blackjack is ReentrancyGuard {
    address public owner;
    uint256 public minBetAmount;
    HouseTreasury public treasury;
    
    struct PlayerHand {
        uint256 bet;
        uint8[] cards;
        bool resolved;
    }
    
    // Create temporary storage for winnings
    struct WinningInfo {
        address player;
        uint256 amount;
    }
    
    mapping(address => PlayerHand) public playerHands;
    mapping(address => bool) public isPlayerActive;
    address[] private activePlayers;

    mapping(address => uint256) private pendingWithdrawals;
    mapping(address => bool) private activeGames;
    bool private resolving;

    bool private paused;
    uint256 private maxWithdrawalAmount = 10 ether;
    mapping(address => uint256) private lastActionTime;
    uint256 private actionCooldown = 1 minutes;

    event BetPlaced(address indexed player, uint256 amount);
    event GameResolved(address indexed player, uint256 winnings);
    event CardDealt(address indexed player, uint8 card);
    event ContractPaused();
    event ContractUnpaused();
    event BetResolved(address indexed player, uint256 amount);

    error BetBelowMinimum();
    error InsufficientTreasuryBalance();
    error PlayerAlreadyHasActiveBet();
    error ActionRateLimited();
    error GamePaused();
    error OnlyOwnerAllowed();
    error ResolutionInProgress();

    constructor(uint256 _minBetAmount, address payable _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwnerAllowed();
        _;
    }

    modifier noActiveGame() {
        if (activeGames[msg.sender]) revert PlayerAlreadyHasActiveBet();
        _;
    }

    modifier notResolving() {
        if (resolving) revert ResolutionInProgress();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert GamePaused();
        _;
    }

    modifier rateLimited() {
        if (block.timestamp < lastActionTime[msg.sender] + actionCooldown) 
            revert ActionRateLimited();
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

    function placeBet() external payable nonReentrant whenNotPaused rateLimited {
        if (msg.value < minBetAmount) 
            revert BetBelowMinimum();
        if (isPlayerActive[msg.sender]) 
            revert PlayerAlreadyHasActiveBet();
        if (!treasury.canPlaceBet(msg.sender, msg.value))
            revert InsufficientTreasuryBalance();

        // Update player state
        playerHands[msg.sender] = PlayerHand({
            bet: msg.value,
            cards: new uint8[](0),
            resolved: false
        });
        
        isPlayerActive[msg.sender] = true;
        activeGames[msg.sender] = true;
        activePlayers.push(msg.sender);
        lastActionTime[msg.sender] = block.timestamp;

        // Process bet in treasury
        treasury.processBetLoss(msg.sender, msg.value);
        
        emit BetPlaced(msg.sender, msg.value);
    }

    function resolveGames(address[] calldata players, uint256[] calldata multipliers) external onlyOwner {
        require(players.length == multipliers.length, "Arrays must be same length");
        
        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            uint256 multiplier = multipliers[i];
            uint256 bet = playerHands[player].bet;
            
            if (multiplier > 0) {
                uint256 winnings = bet * multiplier;
                treasury.processBetWin(player, winnings);
                emit GameResolved(player, winnings);
            }
            
            // Clear player state
            delete playerHands[player];
            activeGames[player] = false;
            isPlayerActive[player] = false;
            
            // Remove from active players array
            for (uint256 j = 0; j < activePlayers.length; j++) {
                if (activePlayers[j] == player) {
                    activePlayers[j] = activePlayers[activePlayers.length - 1];
                    activePlayers.pop();
                    break;
                }
            }
        }
    }

    function getActivePlayers() external view returns (address[] memory) {
        return activePlayers;
    }

    function setActionCooldown(uint256 _cooldown) external onlyOwner {
        actionCooldown = _cooldown;
    }
}