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
    uint256 private actionCooldown = 15 seconds;

    mapping(address => bytes32) public playerGameHashes;
    mapping(bytes32 => bool) public usedHashes;

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

        // Check if treasury has enough funds to cover potential win
        if (treasury.getHouseFunds() < msg.value * 2)
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

        // Transfer bet to treasury
        (bool success, ) = address(treasury).call{value: msg.value}("");
        require(success, "Failed to transfer bet to treasury");
        
        emit BetPlaced(msg.sender, msg.value);
    }

    function resolveGames(address[] calldata players, uint256[] calldata multipliers) 
        external
        whenNotPaused 
    {
        require(players.length == multipliers.length, "Arrays must be same length");
        require(players.length > 0, "No players to resolve");
        
        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            
            // Only owner or the player themselves can resolve their bet
            require(
                msg.sender == owner || msg.sender == player,
                "Only owner or player can resolve bet"
            );
            
            // If not owner, can only resolve own bet
            if (msg.sender != owner) {
                require(player == msg.sender, "Can only resolve own bet");
                require(players.length == 1, "Players can only resolve one bet at a time");
            }
            
            uint256 multiplier = multipliers[i];
            uint256 bet = playerHands[player].bet;
            
            require(bet > 0, "No active bet for player");
            require(isPlayerActive[player], "Player not active");
            
            if (multiplier > 0) {
                // For wins (multiplier = 2) or pushes (multiplier = 1)
                uint256 payout = bet * multiplier;
                
                // Ensure house has enough funds
                require(
                    treasury.getHouseFunds() >= payout, 
                    "Insufficient house funds for payout"
                );
                
                // Process win through treasury
                treasury.processBetWin(player, payout);
                emit GameResolved(player, payout);
            } else {
                // For losses (multiplier = 0), funds stay in treasury
                emit GameResolved(player, 0);
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

    // Add a helper function to get a clean player hand
    function getPlayerHand(address player) external view returns (PlayerHand memory) {
        PlayerHand memory hand = playerHands[player];
        if (hand.cards.length == 0) {
            return PlayerHand({
                bet: 0,
                cards: new uint8[](0),
                resolved: false
            });
        }
        return hand;
    }

    function submitGameResult(
        uint8[] calldata playerCards,
        uint8[] calldata dealerCards,
        uint256 multiplier,
        uint256 nonce
    ) external {
        require(isPlayerActive[msg.sender], "No active game");
        
        // Create a unique hash of the game state
        bytes32 gameHash = keccak256(abi.encodePacked(
            msg.sender,
            playerCards,
            dealerCards,
            multiplier,
            nonce
        ));
        
        // Store the hash for later verification
        playerGameHashes[msg.sender] = gameHash;
    }

    function resolveGameForPlayer(
        address player,
        uint8[] calldata playerCards,
        uint8[] calldata dealerCards,
        uint256 multiplier,
        uint256 nonce
    ) external onlyOwner whenNotPaused {
        // Recreate and verify the game hash
        bytes32 gameHash = keccak256(abi.encodePacked(
            player,
            playerCards,
            dealerCards,
            multiplier,
            nonce
        ));
        
        require(gameHash == playerGameHashes[player], "Invalid game state");
        require(!usedHashes[gameHash], "Game already resolved");
        require(isPlayerActive[player], "Player not active");

        // Mark hash as used
        usedHashes[gameHash] = true;
        
        // Clear the game hash
        delete playerGameHashes[player];

        // Process the game resolution
        uint256 bet = playerHands[player].bet;
        require(bet > 0, "No active bet");

        if (multiplier > 0) {
            uint256 payout = bet * multiplier;
            require(
                treasury.getHouseFunds() >= payout, 
                "Insufficient house funds for payout"
            );
            treasury.processBetWin(player, payout);
            emit GameResolved(player, payout);
        } else {
            emit GameResolved(player, 0);
        }
        
        // Clear player state
        delete playerHands[player];
        isPlayerActive[player] = false;
        
        // Remove from active players array
        for (uint256 i = 0; i < activePlayers.length; i++) {
            if (activePlayers[i] == player) {
                activePlayers[i] = activePlayers[activePlayers.length - 1];
                activePlayers.pop();
                break;
            }
        }
    }
}