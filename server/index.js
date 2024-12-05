require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { ethers } = require('ethers');
const BlackjackJSON = require('../artifacts/contracts/Blackjack.sol/Blackjack.json');
const RouletteJSON = require('../artifacts/contracts/Roulette.sol/Roulette.json');
const TreasuryJSON = require('../artifacts/contracts/HouseTreasury.sol/HouseTreasury.json');

const app = express();
app.use(cors());
app.use(express.json());

// Initialize ethers provider and signer
let provider;
let houseSigner;
let blackjackContract;
let rouletteContract;
let treasuryContract;

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

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
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