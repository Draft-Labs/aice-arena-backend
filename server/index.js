require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { ethers } = require('ethers');
const BlackjackJSON = require('../artifacts/contracts/Blackjack.sol/Blackjack.json');
const RouletteJSON = require('../artifacts/contracts/Roulette.sol/Roulette.json');
const TreasuryJSON = require('../artifacts/contracts/HouseTreasury.sol/HouseTreasury.json');
const PokerJSON = require('../artifacts/contracts/Poker.sol/Poker.json');

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
let pokerContract;

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
  pokerContract = new ethers.Contract(
    process.env.POKER_ADDRESS,
    PokerJSON.abi,
    houseSigner
  );

  // Verify contract ownership and authorize games
  const initializeContracts = async () => {
    try {
      const owner = await treasuryContract.owner();
      const houseSigner_address = await houseSigner.getAddress();
      
      console.log('Contract ownership verification:', {
        owner,
        houseSigner: houseSigner_address,
        isOwner: owner.toLowerCase() === houseSigner_address.toLowerCase()
      });

      if (owner.toLowerCase() !== houseSigner_address.toLowerCase()) {
        throw new Error('House signer is not the contract owner');
      }

      // Authorize game contracts in Treasury
      const rouletteAddress = await rouletteContract.getAddress();
      const blackjackAddress = await blackjackContract.getAddress();
      const pokerAddress = await pokerContract.getAddress();

      // Check if games are already authorized
      const isRouletteAuthorized = await treasuryContract.authorizedGames(rouletteAddress);
      const isBlackjackAuthorized = await treasuryContract.authorizedGames(blackjackAddress);
      const isPokerAuthorized = await treasuryContract.authorizedGames(pokerAddress);

      // Authorize games if needed
      if (!isRouletteAuthorized) {
        console.log('Authorizing Roulette contract...');
        const tx = await treasuryContract.authorizeGame(rouletteAddress);
        await tx.wait();
        console.log('Roulette contract authorized');
      }

      if (!isBlackjackAuthorized) {
        console.log('Authorizing Blackjack contract...');
        const tx = await treasuryContract.authorizeGame(blackjackAddress);
        await tx.wait();
        console.log('Blackjack contract authorized');
      }

      if (!isPokerAuthorized) {
        console.log('Authorizing Poker contract...');
        const tx = await treasuryContract.authorizeGame(pokerAddress);
        await tx.wait();
        console.log('Poker contract authorized');
      }

    } catch (error) {
      console.error('Error initializing contracts:', error);
      throw error;
    }
  };

  initializeContracts();

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
      pokerContract = new ethers.Contract(
        process.env.POKER_ADDRESS,
        PokerJSON.abi,
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
    const { player, betAmount, numbers, betType, nonce } = req.body;

    console.log('Received roulette bet:', {
      player,
      betAmount,
      numbers,
      betType,
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

    // Calculate dynamic gas limit based on number of bets
    const baseGas = 200000;  // Increased base gas
    const gasPerNumber = 75000;  // Increased gas per number
    const gasLimit = baseGas + (numbers.length * gasPerNumber);

    console.log('Gas calculation:', {
      baseGas,
      gasPerNumber,
      numbersLength: numbers.length,
      totalGasLimit: gasLimit
    });

    // Place the bet through the Roulette contract using house signer
    const tx = await rouletteContract.connect(houseSigner).placeBet(
      numbers,
      { 
        value: betAmountWei,
        gasLimit: gasLimit
      }
    );
    
    console.log('Transaction sent:', tx.hash);
    const receipt = await tx.wait();
    console.log('Transaction confirmed:', receipt);

    // Get updated balance after bet
    const newBalance = await treasuryContract.getPlayerBalance(player);

    res.json({ 
      success: true, 
      txHash: tx.hash,
      balance: ethers.formatEther(newBalance)
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
    const maxTables = await pokerContract.maxTables();
    const tables = [];

    for (let i = 0; i < maxTables; i++) {
      const table = await pokerContract.tables(i);
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

    const tx = await pokerContract.createTable(
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
    const playerBalance = await treasuryContract.getPlayerBalance(player);
    if (playerBalance.lt(ethers.parseEther(buyIn.toString()))) {
      throw new Error('Insufficient funds in treasury');
    }

    const tx = await pokerContract.joinTable(
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
    const table = await pokerContract.tables(tableId);
    
    // Get all players at the table
    const players = [];
    const activePlayers = await pokerContract.getTablePlayers(tableId);
    
    for (const playerAddress of activePlayers) {
      const playerInfo = await pokerContract.getPlayerInfo(tableId, playerAddress);
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
        tx = await pokerContract.fold(tableId);
        break;
      case 'check':
        tx = await pokerContract.check(tableId);
        break;
      case 'call':
        tx = await pokerContract.call(tableId);
        break;
      case 'raise':
        tx = await pokerContract.raise(tableId, ethers.parseEther(amount));
        break;
      default:
        throw new Error('Invalid action');
    }

    const receipt = await tx.wait();
    console.log('Action processed:', receipt.hash);

    // Get updated table state
    const tableInfo = await pokerContract.getTableInfo(tableId);
    const playerInfo = await pokerContract.getPlayerInfo(tableId, player);

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
        tx = await pokerContract.startFlop(tableId);
        // Deal 3 flop cards after state change
        await tx.wait();
        cardsTx = await pokerContract.dealCommunityCards(
          tableId, 
          [
            Math.floor(Math.random() * 52) + 1,
            Math.floor(Math.random() * 52) + 1,
            Math.floor(Math.random() * 52) + 1
          ]
        );
        break;
      case 'startTurn':
        tx = await pokerContract.startTurn(tableId);
        // Deal 1 turn card after state change
        await tx.wait();
        cardsTx = await pokerContract.dealCommunityCards(
          tableId, 
          [Math.floor(Math.random() * 52) + 1]
        );
        break;
      case 'startRiver':
        tx = await pokerContract.startRiver(tableId);
        // Deal 1 river card after state change
        await tx.wait();
        cardsTx = await pokerContract.dealCommunityCards(
          tableId, 
          [Math.floor(Math.random() * 52) + 1]
        );
        break;
      case 'startShowdown':
        tx = await pokerContract.startShowdown(tableId);
        break;
      default:
        throw new Error('Invalid dealer action');
    }

    await tx.wait();
    if (cardsTx) await cardsTx.wait();

    // Get updated table state
    const tableInfo = await pokerContract.getTableInfo(tableId);
    const communityCards = await pokerContract.getCommunityCards(tableId);

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
    const players = await pokerContract.getTablePlayers(tableId);
    
    // Deal 2 cards to each active player
    for (const player of players) {
      const playerInfo = await pokerContract.getPlayerInfo(tableId, player);
      if (playerInfo.isActive) {
        await pokerContract.dealPlayerCards(
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

    const tx = await pokerContract.dealPlayerCards(tableId, player, cards);
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

    const tx = await pokerContract.dealCommunityCards(tableId, cards);
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
    const cards = await pokerContract.getPlayerCards(tableId, player);
    
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
    const cards = await pokerContract.getCommunityCards(tableId);
    
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

// Add house player endpoints
app.post('/poker/add-house', async (req, res) => {
  try {
    const { tableId } = req.body;
    
    // Get table info to determine buy-in amount
    const tableInfo = await pokerContract.getTableInfo(tableId);
    const maxBuyIn = tableInfo[1]; // maxBuyIn is the first return value
    
    console.log('House joining table:', {
      tableId,
      maxBuyIn: ethers.formatEther(maxBuyIn)
    });

    // Check if house is already at the table
    const houseAddress = await houseSigner.getAddress();
    const playerInfo = await pokerContract.getPlayerInfo(tableId, houseAddress);
    if (playerInfo[2]) { // isActive is the third return value
      throw new Error('House is already at this table');
    }

    // First ensure house has enough balance in treasury
    const treasuryBalance = await treasuryContract.getPlayerBalance(houseAddress);
    console.log('Treasury balance check:', {
      balance: ethers.formatEther(treasuryBalance),
      required: ethers.formatEther(maxBuyIn)
    });

    // Convert to BigNumber for comparison
    if (treasuryBalance < maxBuyIn) {
      // Add funds to treasury if needed
      const fundAmount = maxBuyIn - treasuryBalance;
      console.log('Depositing to treasury:', ethers.formatEther(fundAmount));
      
      const depositTx = await treasuryContract.connect(houseSigner).deposit({ 
        value: fundAmount,
        gasLimit: 500000
      });
      await depositTx.wait();
      console.log('Deposit complete');
    }

    // Join table with maximum buy-in
    console.log('Joining table with:', ethers.formatEther(maxBuyIn));
    const tx = await pokerContract.connect(houseSigner).joinTable(
      tableId,
      maxBuyIn,
      {
        gasLimit: 500000
      }
    );

    const receipt = await tx.wait();
    console.log('House joined table:', receipt.hash);

    // Start monitoring this table for house's turn
    monitorHousePlay(tableId);

    res.json({
      success: true,
      txHash: receipt.hash,
      houseAddress
    });

  } catch (error) {
    console.error('Error adding house to table:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Update the monitorHousePlay function to handle errors better
const monitorHousePlay = async (tableId) => {
  // Check if monitoring is already active for this table
  if (houseMonitors.has(tableId)) {
    console.log('Monitor already exists for table:', tableId);
    return;
  }
  
  console.log('Starting house monitor for table:', tableId);
  
  const monitor = setInterval(async () => {
    try {
      // Get table info with proper destructuring
      const [
        minBuyIn,
        maxBuyIn,
        smallBlind,
        bigBlind,
        minBet,
        maxBet,
        pot,
        playerCount,
        gameState,
        isActive
      ] = await pokerContract.getTableInfo(tableId);

      // Get current position from the contract directly
      const currentPosition = await pokerContract.tables(tableId).then(table => table.currentPosition);
      
      const houseAddress = await houseSigner.getAddress();
      
      // Get all players at the table
      const players = await pokerContract.getTablePlayers(tableId);
      
      // Debug logging
      console.log('Table state:', {
        tableId,
        currentPosition: currentPosition.toString(),
        gameState: gameState.toString(),
        players,
        houseAddress
      });
      
      // Check if it's house's turn
      if (!players[currentPosition] || 
          players[currentPosition].toLowerCase() !== houseAddress.toLowerCase()) {
        return; // Not house's turn
      }

      console.log('House turn detected:', {
        tableId,
        currentPosition: currentPosition.toString(),
        gameState: gameState.toString()
      });

      // Get game state info
      const [tableStake, currentBet, isPlayerActive, isSittingOut, position] = 
        await pokerContract.getPlayerInfo(tableId, houseAddress);
      
      const houseCards = await pokerContract.getPlayerCards(tableId, houseAddress);
      const communityCards = await pokerContract.getCommunityCards(tableId);

      // Simple house strategy based on hand strength
      const handStrength = evaluateHouseHand(
        houseCards.map(c => Number(c)), 
        communityCards.map(c => Number(c))
      );
      
      console.log('House hand evaluation:', {
        handStrength,
        houseCards: houseCards.map(c => Number(c)),
        communityCards: communityCards.map(c => Number(c)),
        tableStake: ethers.formatEther(tableStake),
        currentBet: ethers.formatEther(currentBet)
      });
      
      let tx;
      
      if (handStrength >= 0.5) { // Strong hand
        // Raise 2x the current bet
        const raiseAmount = currentBet * 2n;
        if (tableStake >= raiseAmount) {
          console.log('House raising:', ethers.formatEther(raiseAmount));
          tx = await pokerContract.connect(houseSigner).raise(tableId, raiseAmount, {
            gasLimit: 500000
          });
        } else {
          console.log('House calling (insufficient funds to raise)');
          tx = await pokerContract.connect(houseSigner).call(tableId, {
            gasLimit: 500000
          });
        }
      } else if (handStrength >= 0.1) { // Medium hand
        // Call or check
        if (currentBet > 0n) {
          console.log('House calling');
          tx = await pokerContract.connect(houseSigner).call(tableId, {
            gasLimit: 500000
          });
        } else {
          console.log('House checking');
          tx = await pokerContract.connect(houseSigner).check(tableId, {
            gasLimit: 500000
          });
        }
      } else { // Weak hand
        // Fold if there's a bet, check if possible
        if (currentBet > 0n) {
          console.log('House folding');
          tx = await pokerContract.connect(houseSigner).fold(tableId, {
            gasLimit: 500000
          });
        } else {
          console.log('House checking (weak hand)');
          tx = await pokerContract.connect(houseSigner).check(tableId, {
            gasLimit: 500000
          });
        }
      }

      const receipt = await tx.wait();
      console.log('House played action:', receipt.hash);

    } catch (error) {
      console.error('Error in house play monitoring:', error);
      
      // If the table is no longer active or house is not in the game, stop monitoring
      if (error.message.includes('Table not active') || 
          error.message.includes('Player not at table')) {
        console.log('Stopping monitor for table:', tableId);
        clearInterval(monitor);
        houseMonitors.delete(tableId);
      }
    }
  }, 3000); // Check every 3 seconds

  houseMonitors.set(tableId, monitor);
};

// Simple hand strength evaluation (0-1 scale)
const evaluateHouseHand = (houseCards, communityCards) => {
  try {
    // Convert card numbers to values and suits
    const allCards = [...houseCards, ...communityCards].map(card => ({
      value: ((card - 1) % 13) + 1,
      suit: Math.floor((card - 1) / 13)
    }));

    // Count pairs, three of a kind, etc.
    const valueCounts = {};
    allCards.forEach(card => {
      valueCounts[card.value] = (valueCounts[card.value] || 0) + 1;
    });

    // Check for pairs, three of a kind, etc.
    const pairs = Object.values(valueCounts).filter(count => count === 2).length;
    const threeOfKind = Object.values(valueCounts).some(count => count === 3);
    const fourOfKind = Object.values(valueCounts).some(count => count === 4);

    // Simple scoring system
    if (fourOfKind) return 1.0;
    if (threeOfKind && pairs > 0) return 0.9;
    if (threeOfKind) return 0.7;
    if (pairs === 2) return 0.6;
    if (pairs === 1) return 0.4;
    
    // High card - scale based on highest card
    const highestCard = Math.max(...allCards.map(card => card.value));
    return 0.2 + (highestCard / 13) * 0.2;

  } catch (error) {
    console.error('Error evaluating house hand:', error);
    return 0.5; // Default to medium strength on error
  }
};

// Keep track of active house monitors
const houseMonitors = new Map();

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