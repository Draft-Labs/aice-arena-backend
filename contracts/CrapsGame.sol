// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;
import "./HouseTreasury.sol";

contract CrapsGame {
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

    event BetPlaced(address indexed player, BetType betType, uint256 amount);
    event GameResolved(address indexed player, uint256 winnings);
    event PointEstablished(uint8 point);
    event RollResult(uint8 roll);

    constructor(uint256 _minBetAmount, address _treasuryAddress) {
        owner = msg.sender;
        minBetAmount = _minBetAmount;
        treasury = HouseTreasury(_treasuryAddress);
        currentPhase = GamePhase.Off;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    function placeBet(BetType betType) external payable {
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

    function resolveRoll(uint8 rollOutcome) external onlyOwner {
        require(rollOutcome >= 2 && rollOutcome <= 12, "Invalid roll outcome.");
        emit RollResult(rollOutcome);

        for (uint256 i = 0; i < activePlayers.length; i++) {
            address player = activePlayers[i];
            
            for (uint8 j = 0; j < 8; j++) {
                BetType betType = BetType(j);
                Bet storage bet = playerBets[player][betType];
                
                if (bet.amount > 0 && !bet.resolved) {
                    uint256 winnings = calculateWinnings(bet, rollOutcome);
                    if (winnings > 0) {
                        treasury.payout(player, winnings);
                        emit GameResolved(player, winnings);
                    }
                    // Mark bet as resolved regardless of win/loss
                    bet.resolved = true;
                }
            }
        }

        // Update game phase and point based on roll
        updateGameState(rollOutcome);
        
        // Clear resolved bets
        clearResolvedBets();
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
}