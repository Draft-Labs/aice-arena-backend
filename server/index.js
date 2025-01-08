require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { ethers } = require('ethers');
const BlackjackJSON = require('../artifacts/contracts/Blackjack.sol/Blackjack.json');
const RouletteJSON = require('../artifacts/contracts/Roulette.sol/Roulette.json');
const TreasuryJSON = require('../artifacts/contracts/HouseTreasury.sol/HouseTreasury.json');
const PokerTableJSON = require('../artifacts/contracts/poker/PokerTable.sol/PokerTable.json');
const PokerBettingJSON = require('../artifacts/contracts/poker/PokerBetting.sol/PokerBetting.json');
const PokerPlayerManagerJSON = require('../artifacts/contracts/poker/PokerPlayerManager.sol/PokerPlayerManager.json');
const PokerGameStateJSON = require('../artifacts/contracts/poker/PokerGameState.sol/PokerGameState.json');
const PokerTreasuryJSON = require('../artifacts/contracts/poker/PokerTreasury.sol/PokerTreasury.json');

const app = express();
app.use(cors({
  origin: ['http://localhost:3000', 'http://localhost:5173'],
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));
app.use(express.json());

// Initialize ethers provider and signer
let provider;
let houseSigner;
let blackjackContract;
let rouletteContract;
let treasuryContract;
let pokerTableContract;
let pokerBettingContract;
let pokerPlayerManagerContract;
let pokerGameStateContract;
let pokerTreasuryContract;

const EXPECTED_CHAIN_ID = 31337; // Hardhat's default chain ID

try {
  // Initialize provider with just the URL
  provider = new ethers.JsonRpcProvider('http://127.0.0.1:8545', {
    chainId: EXPECTED_CHAIN_ID,
    name: 'hardhat'
  });
  
  houseSigner = new ethers.Wallet(process.env.HOUSE_PRIVATE_KEY, provider);
  blackjackContract = new ethers.Contract(
    process.env.BLACKJACK_ADDRESS,
    BlackjackJSON.abi,
    houseSigner
  );
  rouletteContract = new ethers.Contract(
    process.env.ROULETTE_ADDRESS,
    RouletteJSON.abi,
    houseSigner
  );
  treasuryContract = new ethers.Contract(
    process.env.TREASURY_ADDRESS,
    TreasuryJSON.abi,
    houseSigner
  );
  pokerTableContract = new ethers.Contract(
    process.env.POKER_TABLE_ADDRESS,
    PokerTableJSON.abi,
    houseSigner
  );
  pokerBettingContract = new ethers.Contract(
    process.env.POKER_BETTING_ADDRESS,
    PokerBettingJSON.abi,
    houseSigner
  );
  pokerPlayerManagerContract = new ethers.Contract(
    process.env.POKER_PLAYER_MANAGER_ADDRESS,
    PokerPlayerManagerJSON.abi,
    houseSigner
  );
  pokerGameStateContract = new ethers.Contract(
    process.env.POKER_GAME_STATE_ADDRESS,
    PokerGameStateJSON.abi,
    houseSigner
  );
  pokerTreasuryContract = new ethers.Contract(
    process.env.POKER_TREASURY_ADDRESS,
    PokerTreasuryJSON.abi,
    houseSigner
  );

  // Verify contract ownership
  const verifyOwnership = async () => {
    try {
      const owner = await blackjackContract.owner();
      const houseSigner_address = await houseSigner.getAddress();
      
      console.log('Contract ownership verification:', {
        owner,
        houseSigner: houseSigner_address,
        isOwner: owner.toLowerCase() === houseSigner_address.toLowerCase()
      });

      if (owner.toLowerCase() !== houseSigner_address.toLowerCase()) {
        throw new Error('House signer is not the contract owner');
      }
    } catch (error) {
      console.error('Error verifying contract ownership:', error);
      throw error;
    }
  };

  verifyOwnership();

  // Test connection immediately
  provider.getNetwork().then(network => {
    console.log('Successfully connected to network:', {
      chainId: network.chainId,
      name: network.name
    });
  }).catch(error => {
    console.error('Failed to connect to network:', error);
  });

} catch (error) {
  console.error('Error initializing blockchain connection:', error);
}

// Add connection retry logic
async function ensureConnection() {
  try {
    if (!provider) {
      provider = new ethers.JsonRpcProvider('http://127.0.0.1:8545', {
        chainId: EXPECTED_CHAIN_ID,
        name: 'hardhat'
      });
      houseSigner = new ethers.Wallet(process.env.HOUSE_PRIVATE_KEY, provider);
      blackjackContract = new ethers.Contract(
        process.env.BLACKJACK_ADDRESS,
        BlackjackJSON.abi,
        houseSigner
      );
      rouletteContract = new ethers.Contract(
        process.env.ROULETTE_ADDRESS,
        RouletteJSON.abi,
        houseSigner
      );
      treasuryContract = new ethers.Contract(
        process.env.TREASURY_ADDRESS,
        TreasuryJSON.abi,
        houseSigner
      );
      pokerTableContract = new ethers.Contract(
        process.env.POKER_TABLE_ADDRESS,
        PokerTableJSON.abi,
        houseSigner
      );
      pokerBettingContract = new ethers.Contract(
        process.env.POKER_BETTING_ADDRESS,
        PokerBettingJSON.abi,
        houseSigner
      );
      pokerPlayerManagerContract = new ethers.Contract(
        process.env.POKER_PLAYER_MANAGER_ADDRESS,
        PokerPlayerManagerJSON.abi,
        houseSigner
      );
      pokerGameStateContract = new ethers.Contract(
        process.env.POKER_GAME_STATE_ADDRESS,
        PokerGameStateJSON.abi,
        houseSigner
      );
      pokerTreasuryContract = new ethers.Contract(
        process.env.POKER_TREASURY_ADDRESS,
        PokerTreasuryJSON.abi,
        houseSigner
      );
    }
    const network = await provider.getNetwork();
    return true;
  } catch (error) {
    console.error('Connection failed, retrying...', error);
    return false;
  }
}

// Add a connection check endpoint with chain ID verification
app.get('/status', async (req, res) => {
  try {
    const network = await provider.getNetwork();
    if (network.chainId !== EXPECTED_CHAIN_ID) {
      throw new Error(`Wrong network. Expected chain ID ${EXPECTED_CHAIN_ID}, got ${network.chainId}`);
    }
    res.json({
      status: 'connected',
      network: network.name,
      chainId: network.chainId
    });
  } catch (error) {
    res.status(500).json({
      status: 'disconnected',
      error: error.message
    });
  }
});

// Verify game result helper function
function verifyGameResult(playerHand, dealerHand) {
  // Calculate player score
  let playerScore = calculateHandScore(playerHand);
  let dealerScore = calculateHandScore(dealerHand);

  console.log('Backend score calculation:', {
    playerScore,
    dealerScore,
    playerHand,
    dealerHand,
    playerCards: playerHand.map(card => ({
      card,
      value: card % 13 || 13,
      score: calculateHandScore([card])
    })),
    dealerCards: dealerHand.map(card => ({
      card,
      value: card % 13 || 13,
      score: calculateHandScore([card])
    }))
  });

  // Match frontend logic exactly
  if (playerScore > 21) {
    console.log('Player bust - dealer wins');
    return 0; // Player bust
  }
  if (dealerScore > 21) {
    console.log('Dealer bust - player wins');
    return 2; // Dealer bust, player wins
  }
  if (dealerScore === playerScore) {
    console.log('Equal scores - push');
    return 1; // Push
  }
  if (dealerScore > playerScore) {
    console.log('Dealer score higher - dealer wins');
    return 0; // Dealer wins
  }
  if (dealerScore < playerScore) {
    console.log('Player score higher - player wins');
    return 2; // Player wins
  }
  
  console.log('Unknown game state');
  return 0;
}

function calculateHandScore(hand) {
  let score = 0;
  let aces = 0;

  console.log('Starting hand calculation:', hand);

  hand.forEach(card => {
    // Match frontend calculation exactly
    let value = card % 13 || 13;  // This is the key line that needs to match

    console.log('Processing card:', {
      originalCard: card,
      modResult: card % 13,
      valueAfterMod: value
    });

    if (value > 10) value = 10;
    if (value === 1) {
      aces += 1;
      value = 11;
    }

    console.log('Card value after processing:', {
      finalValue: value,
      isAce: value === 11,
      currentScore: score,
      newScore: score + value
    });

    score += value;
  });

  // Adjust for aces
  while (score > 21 && aces > 0) {
    score -= 10;
    aces -= 1;
    console.log('Adjusted for ace:', {
      newScore: score,
      remainingAces: aces
    });
  }

  console.log('Final hand calculation:', {
    originalHand: hand,
    finalScore: score,
    remainingAces: aces
  });

  return score;
}

// Endpoint to handle game resolution
app.post('/submit-game', async (req, res) => {
  try {
    const { player, playerHand, dealerHand, multiplier, nonce } = req.body;

    console.log('Received game submission:', {
      player,
      playerHand,
      dealerHand,
      multiplier,
      nonce
    });

    const playerScore = calculateHandScore(playerHand);
    const dealerScore = calculateHandScore(dealerHand);

    console.log('Score calculation:', {
      playerHand,
      dealerHand,
      playerScore,
      dealerScore,
      playerBust: playerScore > 21
    });

    // Verify the game result matches what the frontend calculated
    const expectedMultiplier = verifyGameResult(playerHand, dealerHand);
    console.log('Game result determination:', {
      playerScore,
      dealerScore,
      expectedMultiplier,
      receivedMultiplier: multiplier,
      playerBust: playerScore > 21,
      dealerBust: dealerScore > 21
    });

    if (expectedMultiplier !== multiplier) {
      throw new Error(`Invalid multiplier. Expected ${expectedMultiplier}, got ${multiplier}. Scores: player=${playerScore} (${playerHand.join(',')}), dealer=${dealerScore} (${dealerHand.join(',')})`);
    }

    // Verify contract ownership first
    const owner = await blackjackContract.owner();
    const houseSigner_address = await houseSigner.getAddress();
    console.log('Contract ownership check:', {
      owner,
      houseSigner: houseSigner_address,
      isOwner: owner.toLowerCase() === houseSigner_address.toLowerCase()
    });

    // Check player status with more details
    const isActive = await blackjackContract.isPlayerActive(player);
    let playerState;
    try {
      playerState = await blackjackContract.playerHands(player);
      console.log('Raw player state:', {
        playerState,
        type: typeof playerState,
        keys: Object.keys(playerState || {}),
        isArray: Array.isArray(playerState)
      });
    } catch (error) {
      console.error('Error getting player state:', error);
      playerState = {};
    }

    // Safely access player state properties with more defensive checks
    const gameState = {
      player,
      isActive,
      bet: '0',
      hasCards: false,
      resolved: false,
      activeGames: [],
      isInActiveList: false
    };

    try {
      // Try to get bet amount
      if (playerState && typeof playerState.bet !== 'undefined') {
        gameState.bet = playerState.bet.toString();
      }

      // Try to get cards
      if (playerState && playerState.cards) {
        gameState.hasCards = Array.isArray(playerState.cards) ? playerState.cards.length > 0 : false;
      }

      // Try to get resolved status
      if (playerState && typeof playerState.resolved !== 'undefined') {
        gameState.resolved = Boolean(playerState.resolved);
      }

      // Get active games list
      const activeGames = await blackjackContract.getActivePlayers();
      gameState.activeGames = activeGames;
      gameState.isInActiveList = activeGames.includes(player);
    } catch (error) {
      console.error('Error processing game state:', error);
    }
    
    console.log('Processed game state:', gameState);

    if (!isActive) {
      throw new Error(`No active game found for player. Active games: ${gameState.activeGames.join(', ')}`);
    }

    // Add delay before resolution (sometimes helps with race conditions)
    await new Promise(resolve => setTimeout(resolve, 1000));

    console.log('Resolving game with params:', {
      player,
      multiplier,
      signer: houseSigner_address,
      isOwner: owner.toLowerCase() === houseSigner_address.toLowerCase()
    });

    const resolveTx = await blackjackContract.resolveGames(
      [player],
      [multiplier],
      {
        gasLimit: 500000
      }
    );

    console.log('Transaction sent:', resolveTx.hash);
    const receipt = await resolveTx.wait();
    console.log('Transaction receipt:', {
      status: receipt.status,
      hash: receipt.hash,
      from: receipt.from,
      to: receipt.to
    });

    res.json({
      success: true,
      txHash: resolveTx.hash
    });

  } catch (error) {
    console.error('Detailed error:', {
      message: error.message,
      stack: error.stack,
      type: error.code || 'UNKNOWN_ERROR',
      error
    });
    res.status(500).json({
      success: false,
      error: error.message,
      details: {
        stack: error.stack,
        type: error.code || 'UNKNOWN_ERROR'
      }
    });
  }
});

// Add new endpoints for roulette
app.post('/submit-roulette-bet', async (req, res) => {
  try {
    const { player, betAmount, betType, numbers, nonce } = req.body;

    console.log('Received roulette bet:', {
      player,
      betAmount,
      betType,
      numbers,
      nonce
    });

    // Verify player has an active account in Treasury
    const hasAccount = await treasuryContract.activeAccounts(player);
    if (!hasAccount) {
      throw new Error('No active account found');
    }

    // Verify player has sufficient balance
    const playerBalance = await treasuryContract.getPlayerBalance(player);
    const betAmountWei = ethers.parseEther(betAmount.toString());
    if (playerBalance < betAmountWei) {
      throw new Error('Insufficient balance');
    }

    // Process the bet through the treasury first
    await treasuryContract.processBetLoss(player, betAmountWei);

    // Then place the bet in the roulette contract
    const tx = await rouletteContract.placeBet(
      betType,
      numbers,
      betAmountWei,
      {
        gasLimit: 500000
      }
    );
    
    console.log('Transaction sent:', tx.hash);
    const receipt = await tx.wait();
    console.log('Transaction confirmed:', receipt);

    res.json({ 
      success: true, 
      txHash: tx.hash,
      balance: ethers.formatEther(await treasuryContract.getPlayerBalance(player))
    });
  } catch (error) {
    console.error('Error in submit-roulette-bet:', error);
    res.status(500).json({ 
      error: error.message,
      details: error.stack
    });
  }
});

app.post('/resolve-roulette-bet', async (req, res) => {
  try {
    const { player, spinResult, nonce } = req.body;

    console.log('Resolving roulette bet:', {
      player,
      spinResult,
      nonce
    });

    // Spin the wheel using house wallet
    const tx = await rouletteContract.spin(
      spinResult,
      {
        gasLimit: 500000
      }
    );

    console.log('Transaction sent:', tx.hash);
    const receipt = await tx.wait();
    console.log('Transaction confirmed:', receipt);

    res.json({
      success: true,
      txHash: tx.hash,
      result: spinResult
    });

  } catch (error) {
    console.error('Error resolving roulette bet:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Add poker routes
app.get('/poker/tables', async (req, res) => {
  try {
    const maxTables = await pokerTableContract.maxTables();
    const tables = [];

    for (let i = 0; i < maxTables; i++) {
      const table = await pokerTableContract.tables(i);
      if (table.isActive) {
        tables.push({
          id: i,
          minBuyIn: ethers.formatEther(table.minBuyIn),
          maxBuyIn: ethers.formatEther(table.maxBuyIn),
          smallBlind: ethers.formatEther(table.smallBlind),
          bigBlind: ethers.formatEther(table.bigBlind),
          playerCount: table.playerCount.toString(),
          isActive: table.isActive
        });
      }
    }

    res.json({ success: true, tables });
  } catch (error) {
    console.error('Error fetching tables:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

app.post('/poker/create-table', async (req, res) => {
  try {
    const { minBuyIn, maxBuyIn, smallBlind, bigBlind } = req.body;

    console.log('Creating poker table:', {
      minBuyIn,
      maxBuyIn,
      smallBlind,
      bigBlind
    });

    const tx = await pokerTableContract.createTable(
      ethers.parseEther(minBuyIn.toString()),
      ethers.parseEther(maxBuyIn.toString()),
      ethers.parseEther(smallBlind.toString()),
      ethers.parseEther(bigBlind.toString()),
      {
        gasLimit: 500000
      }
    );

    const receipt = await tx.wait();
    console.log('Table created:', receipt.hash);

    res.json({
      success: true,
      txHash: receipt.hash
    });

  } catch (error) {
    console.error('Error creating table:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.post('/poker/join-table', async (req, res) => {
  try {
    const { player, tableId, buyIn } = req.body;

    console.log('Player joining table:', {
      player,
      tableId,
      buyIn
    });

    // Verify player has sufficient funds in treasury
    const playerBalance = await pokerTreasuryContract.getPlayerBalance(player);
    if (playerBalance.lt(ethers.parseEther(buyIn.toString()))) {
      throw new Error('Insufficient funds in treasury');
    }

    const tx = await pokerPlayerManagerContract.joinTable(
      tableId,
      ethers.parseEther(buyIn.toString()),
      {
        gasLimit: 500000
      }
    );

    const receipt = await tx.wait();
    console.log('Player joined table:', receipt.hash);

    res.json({
      success: true,
      txHash: receipt.hash
    });

  } catch (error) {
    console.error('Error joining table:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.get('/poker/table/:tableId', async (req, res) => {
  try {
    const { tableId } = req.params;
    const table = await pokerTableContract.tables(tableId);
    
    // Get all players at the table
    const players = [];
    const activePlayers = await pokerPlayerManagerContract.getTablePlayers(tableId);
    
    for (const playerAddress of activePlayers) {
      const playerInfo = await pokerPlayerManagerContract.getPlayerInfo(tableId, playerAddress);
      players.push({
        address: playerAddress,
        tableStake: ethers.formatEther(playerInfo.tableStake),
        currentBet: ethers.formatEther(playerInfo.currentBet),
        isActive: playerInfo.isActive,
        isSittingOut: playerInfo.isSittingOut,
        position: playerInfo.position
      });
    }

    res.json({
      success: true,
      table: {
        minBuyIn: ethers.formatEther(table.minBuyIn),
        maxBuyIn: ethers.formatEther(table.maxBuyIn),
        smallBlind: ethers.formatEther(table.smallBlind),
        bigBlind: ethers.formatEther(table.bigBlind),
        playerCount: table.playerCount.toString(),
        isActive: table.isActive,
        gameState: table.gameState,
        players
      }
    });

  } catch (error) {
    console.error('Error fetching table:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Add these new poker game action endpoints
app.post('/poker/action', async (req, res) => {
  try {
    const { tableId, player, action, amount = '0' } = req.body;
    
    console.log('Player action:', {
      tableId,
      player,
      action,
      amount
    });

    let tx;
    switch (action) {
      case 'fold':
        tx = await pokerBettingContract.fold(tableId);
        break;
      case 'check':
        tx = await pokerBettingContract.check(tableId);
        break;
      case 'call':
        tx = await pokerBettingContract.call(tableId);
        break;
      case 'raise':
        tx = await pokerBettingContract.raise(tableId, ethers.parseEther(amount));
        break;
      default:
        throw new Error('Invalid action');
    }

    const receipt = await tx.wait();
    console.log('Action processed:', receipt.hash);

    // Get updated table state
    const tableInfo = await pokerTableContract.getTableInfo(tableId);
    const playerInfo = await pokerPlayerManagerContract.getPlayerInfo(tableId, player);

    res.json({
      success: true,
      txHash: receipt.hash,
      tableState: {
        gameState: tableInfo.gameState,
        pot: ethers.formatEther(tableInfo.pot),
        currentBet: ethers.formatEther(playerInfo.currentBet),
        isPlayerTurn: playerInfo.isActive && !playerInfo.isSittingOut
      }
    });

  } catch (error) {
    console.error('Error processing player action:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.post('/poker/dealer-action', async (req, res) => {
  try {
    const { tableId, action } = req.body;
    
    console.log('Dealer action:', {
      tableId,
      action
    });

    let tx;
    let cardsTx;
    
    // First change game state
    switch (action) {
      case 'startFlop':
        tx = await pokerGameStateContract.startFlop(tableId);
        // Deal 3 flop cards after state change
        await tx.wait();
        cardsTx = await pokerTableContract.dealCommunityCards(
          tableId, 
          [
            Math.floor(Math.random() * 52) + 1,
            Math.floor(Math.random() * 52) + 1,
            Math.floor(Math.random() * 52) + 1
          ]
        );
        break;
      case 'startTurn':
        tx = await pokerGameStateContract.startTurn(tableId);
        // Deal 1 turn card after state change
        await tx.wait();
        cardsTx = await pokerTableContract.dealCommunityCards(
          tableId, 
          [Math.floor(Math.random() * 52) + 1]
        );
        break;
      case 'startRiver':
        tx = await pokerGameStateContract.startRiver(tableId);
        // Deal 1 river card after state change
        await tx.wait();
        cardsTx = await pokerTableContract.dealCommunityCards(
          tableId, 
          [Math.floor(Math.random() * 52) + 1]
        );
        break;
      case 'startShowdown':
        tx = await pokerGameStateContract.startShowdown(tableId);
        break;
      default:
        throw new Error('Invalid dealer action');
    }

    await tx.wait();
    if (cardsTx) await cardsTx.wait();

    // Get updated table state
    const tableInfo = await pokerTableContract.getTableInfo(tableId);
    const communityCards = await pokerTableContract.getCommunityCards(tableId);

    res.json({
      success: true,
      txHash: tx.hash,
      gameState: tableInfo.gameState,
      communityCards: communityCards.map(card => Number(card))
    });

  } catch (error) {
    console.error('Error processing dealer action:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Add a new endpoint to deal initial player cards
app.post('/poker/deal-initial-cards', async (req, res) => {
  try {
    const { tableId } = req.body;
    
    // Get all players at the table
    const players = await pokerPlayerManagerContract.getTablePlayers(tableId);
    
    // Deal 2 cards to each active player
    for (const player of players) {
      const playerInfo = await pokerPlayerManagerContract.getPlayerInfo(tableId, player);
      if (playerInfo.isActive) {
        await pokerTableContract.dealPlayerCards(
          tableId,
          player,
          [
            Math.floor(Math.random() * 52) + 1,
            Math.floor(Math.random() * 52) + 1
          ]
        );
      }
    }

    res.json({
      success: true,
      message: 'Initial cards dealt to all players'
    });

  } catch (error) {
    console.error('Error dealing initial cards:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// Add these new endpoints for dealing cards

app.post('/poker/deal-player-cards', async (req, res) => {
  try {
    const { tableId, player } = req.body;
    
    // Generate random cards (1-52)
    const cards = [
      Math.floor(Math.random() * 52) + 1,
      Math.floor(Math.random() * 52) + 1
    ];
    
    console.log('Dealing player cards:', {
      tableId,
      player,
      cards
    });

    const tx = await pokerTableContract.dealPlayerCards(tableId, player, cards);
    const receipt = await tx.wait();

    res.json({
      success: true,
      txHash: receipt.hash,
      cards
    });

  } catch (error) {
    console.error('Error dealing player cards:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.post('/poker/deal-community-cards', async (req, res) => {
  try {
    const { tableId, stage } = req.body;
    
    // Generate random cards based on stage
    let cards;
    if (stage === 'flop') {
      cards = Array(3).fill().map(() => Math.floor(Math.random() * 52) + 1);
    } else if (stage === 'turn' || stage === 'river') {
      cards = [Math.floor(Math.random() * 52) + 1];
    } else {
      throw new Error('Invalid stage');
    }
    
    console.log('Dealing community cards:', {
      tableId,
      stage,
      cards
    });

    const tx = await pokerTableContract.dealCommunityCards(tableId, cards);
    const receipt = await tx.wait();

    res.json({
      success: true,
      txHash: receipt.hash,
      cards
    });

  } catch (error) {
    console.error('Error dealing community cards:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Add endpoints to get cards
app.get('/poker/player-cards/:tableId/:player', async (req, res) => {
  try {
    const { tableId, player } = req.params;
    const cards = await pokerTableContract.getPlayerCards(tableId, player);
    
    res.json({
      success: true,
      cards: cards.map(card => Number(card))
    });
  } catch (error) {
    console.error('Error getting player cards:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.get('/poker/community-cards/:tableId', async (req, res) => {
  try {
    const { tableId } = req.params;
    const cards = await pokerTableContract.getCommunityCards(tableId);
    
    res.json({
      success: true,
      cards: cards.map(card => Number(card))
    });
  } catch (error) {
    console.error('Error getting community cards:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Add helper function to convert card numbers to readable format
function getCardDetails(cardNumber) {
  const suits = ['♠', '♣', '♥', '♦'];
  const values = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
  
  const suitIndex = Math.floor((cardNumber - 1) / 13);
  const valueIndex = (cardNumber - 1) % 13;
  
  return {
    suit: suits[suitIndex],
    value: values[valueIndex],
    color: suitIndex >= 2 ? 'red' : 'black'
  };
}

const PORT = process.env.PORT || 3001;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({
    success: false,
    error: 'Internal server error'
  });
}); 