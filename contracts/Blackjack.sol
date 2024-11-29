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

    error PlayerAlreadyHasActiveBet();
    error OnlyOwnerAllowed();
    error ActionRateLimited();

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
        require(!resolving, "Resolution in progress");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
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

    function placeBet() external payable nonReentrant noActiveGame whenNotPaused rateLimited {
        require(msg.value >= minBetAmount, "Bet amount too low");
        require(treasury.canPlaceBet(msg.sender, msg.value), "Insufficient balance or no active account");
        
        // Process the bet amount from their treasury balance
        treasury.processBetLoss(msg.sender, msg.value);

        activeGames[msg.sender] = true;
        playerHands[msg.sender] = PlayerHand({
            bet: msg.value,
            cards: new uint8[](0),
            resolved: false
        });
        activePlayers.push(msg.sender);
        
        emit BetPlaced(msg.sender, msg.value);
    }

    function resolveGames(address[] calldata winners, uint8[] calldata multipliers) external onlyOwner nonReentrant notResolving {
        resolving = true;
        require(winners.length == multipliers.length, "Arrays length mismatch");
        
        WinningInfo[] memory winnings = new WinningInfo[](winners.length);
        uint256 winningCount = 0;

        // Calculate all winnings and update state
        for (uint256 i = 0; i < winners.length; i++) {
            address player = winners[i];
            require(playerHands[player].bet > 0, "No active bet for player");
            require(!playerHands[player].resolved, "Game already resolved");
            
            uint256 winningAmount = playerHands[player].bet * multipliers[i];
            if (winningAmount > 0) {
                winnings[winningCount] = WinningInfo({
                    player: player,
                    amount: winningAmount
                });
                winningCount++;
            }
            
            playerHands[player].resolved = true;
        }
        
        // Clear all active games
        for (uint256 i = 0; i < activePlayers.length; i++) {
            delete playerHands[activePlayers[i]];
            activeGames[activePlayers[i]] = false;
        }
        delete activePlayers;

        // Process all payouts through treasury
        for (uint256 i = 0; i < winningCount; i++) {
            treasury.processBetWin(winnings[i].player, winnings[i].amount);
            emit GameResolved(winnings[i].player, winnings[i].amount);
        }
        resolving = false;
    }

    function getActivePlayers() external view returns (address[] memory) {
        return activePlayers;
    }

    function setActionCooldown(uint256 _cooldown) external onlyOwner {
        actionCooldown = _cooldown;
    }
}