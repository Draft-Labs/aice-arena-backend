// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./HouseTreasury.sol";

contract Roulette is Ownable, ReentrancyGuard, Pausable {
    using Math for uint256;

    HouseTreasury treasury;

    uint256 public minBetAmount = 0.1 ether;
    bool public resolving = false;

    struct Bet {
        address player;
        uint256 amount;
        uint8 number;
    }

    struct WinningInfo {
        address player;
        uint256 amount;
    }

    mapping(address => Bet[]) public playerBets;
    address[] public activePlayers;

    event BetPlaced(address indexed player, uint256 amount, uint8 number);
    event SpinResult(uint8 result);
    event GameResult(uint8 result, uint256 payout, bool won);
    event Payout(address indexed player, uint256 amount);

    constructor(HouseTreasury _treasury) Ownable(msg.sender) {
        treasury = _treasury;
    }

    function placeBet(uint8[] calldata numbers) external payable nonReentrant whenNotPaused {
        require(msg.value >= minBetAmount * numbers.length, "Bet amount below minimum");
        require(numbers.length > 0, "Must bet on at least one number");
        require(msg.value * 2 <= address(treasury).balance, "Payout exceeds treasury balance");
        require(msg.value < 100 ether, "Payout exceeds max bet amount");
        
        uint256 individualBetAmount = msg.value / numbers.length;
        require(individualBetAmount >= minBetAmount, "Individual bet amount below minimum");
        
        (bool success, ) = address(treasury).call{value: msg.value}("");
        require(success, "Transfer to treasury failed");
        
        if (playerBets[msg.sender].length == 0) {
            activePlayers.push(msg.sender);
        }
        
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

    function placeBetAndSpin(uint8[] calldata numbers) external payable nonReentrant whenNotPaused {
        require(msg.value >= minBetAmount * numbers.length, "Bet amount below minimum");
        require(numbers.length > 0, "Must bet on at least one number");
        require(msg.value * 2 <= address(treasury).balance, "Payout exceeds treasury balance");
        require(msg.value < 100 ether, "Payout exceeds max bet amount");
        
        uint256 individualBetAmount = msg.value / numbers.length;
        require(individualBetAmount >= minBetAmount, "Individual bet amount below minimum");
        
        (bool success, ) = address(treasury).call{value: msg.value}("");
        require(success, "Transfer to treasury failed");

        if (playerBets[msg.sender].length == 0) {
            activePlayers.push(msg.sender);
        }
        
        uint256 calculatedTotal = individualBetAmount * numbers.length;
        if (calculatedTotal < msg.value) {
            individualBetAmount = msg.value / numbers.length;
            uint256 remainder = msg.value - calculatedTotal;
            
            playerBets[msg.sender].push(Bet({
                player: msg.sender,
                amount: individualBetAmount + remainder,
                number: numbers[0]
            }));
            
            emit BetPlaced(msg.sender, individualBetAmount + remainder, numbers[0]);
            
            for (uint256 i = 1; i < numbers.length; i++) {
                require(numbers[i] <= 36, "Invalid roulette number");
                
                playerBets[msg.sender].push(Bet({
                    player: msg.sender,
                    amount: individualBetAmount,
                    number: numbers[i]
                }));
                
                emit BetPlaced(msg.sender, individualBetAmount, numbers[i]);
            }
        } else {
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
        
        uint8 result = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, blockhash(block.number - 1)))) % 37);
        _spin(result);
    }

    function _spin(uint8 result) private {
        resolving = true;
        require(result <= 36, "Invalid roulette number.");
        emit SpinResult(result);

        WinningInfo[] memory winnings = new WinningInfo[](activePlayers.length * 10);
        uint256 winningCount = 0;

        for (uint256 p = 0; p < activePlayers.length; p++) {
            address player = activePlayers[p];
            Bet[] storage playerBetList = playerBets[player];

            for (uint256 i = 0; i < playerBetList.length; i++) {
                Bet memory bet = playerBetList[i];
                
                if (bet.number == result) {
                    uint256 winningAmount = bet.amount * 36;
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
            
            delete playerBets[player];
        }

        delete activePlayers;

        for (uint256 i = 0; i < winningCount; i++) {
            treasury.processBetWin(winnings[i].player, winnings[i].amount);
            emit Payout(winnings[i].player, winnings[i].amount);
        }
        resolving = false;
    }

    function spin(uint8 result) external nonReentrant notResolving {
        require(msg.sender == owner(), "Only owner can call this function");
        _spin(result);
    }

    modifier notResolving() {
        require(!resolving, "Game is currently resolving");
        _;
    }
}