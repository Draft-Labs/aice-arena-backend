# Poker Contract Refactoring Plan

## 1. Core Contracts Structure

### 1.1 Interfaces
- `IPokerBase.sol`: Base interface containing shared types and events
- `IPokerGame.sol`: Game logic interface (betting, turns, etc.)
- `IPokerTable.sol`: Table management interface
- `IPokerHand.sol`: Hand evaluation interface

### 1.2 Implementation Contracts
- `PokerBase.sol`: Implements shared types, structs, and events
- `PokerGame.sol`: Core game logic implementation
- `PokerTable.sol`: Table management implementation
- `PokerHand.sol`: Hand evaluation implementation
- `PokerMain.sol`: Main contract that inherits all implementations

## 2. Interface Definitions

### 2.1 IPokerBase.sol
- Enums: `HandRank`, `GameState`
- Structs: `Player`, `Table`
- Events: `TableCreated`, `PlayerJoined`, etc.

### 2.2 IPokerGame.sol
- Functions:
  - `placeBet()`
  - `fold()`
  - `call()`
  - `raise()`
  - `check()`
  - Game state transitions

### 2.3 IPokerTable.sol
- Functions:
  - `createTable()`
  - `joinTable()`
  - `leaveTable()`
  - Table management operations

### 2.4 IPokerHand.sol
- Functions:
  - `evaluateHand()`
  - `dealCards()`
  - Card management operations

## 3. Implementation Details

### 3.1 PokerBase.sol
- Implements basic structs and mappings
- Shared modifiers
- Common utility functions
- Storage layout

### 3.2 PokerGame.sol
- Betting logic
- Turn management
- Round progression
- Pot management

### 3.3 PokerTable.sol
- Table creation/deletion
- Player management
- Buy-in handling
- Table state management

### 3.4 PokerHand.sol
- Hand evaluation algorithms
- Card dealing logic
- Deck management
- Winner determination

### 3.5 PokerMain.sol
- Inherits all implementation contracts
- Manages contract interactions
- Handles treasury integration
- Access control

## 4. Storage Optimization

### 4.1 Storage Layout
- Move rarely accessed data to separate storage contracts
- Use packed structs where possible
- Optimize mapping structures

### 4.2 Event Optimization
- Reduce event parameter size
- Combine related events
- Index important parameters

## 5. Frontend Integration

### 5.1 Contract Updates
- Update contract addresses in environment variables
- Modify ABI imports to reflect new contract structure
- Update contract interaction methods

### 5.2 Component Updates
- Update contract calls to new structure
- Modify state management
- Update event listeners

## 6. Backend Integration

### 6.1 Server Updates
- Modify contract listeners
- Update house play logic
- Test monitoring systems

## 7. Migration Plan

1. Deploy new contracts in this order:
   - PokerBase
   - PokerHand
   - PokerTable
   - PokerGame
   - PokerMain

2. Update frontend:
   - Update contract addresses
   - Test all interactions
   - Verify event handling

3. Update backend:
   - Modify contract listeners
   - Update house play logic
   - Test monitoring systems

4. Data Migration:
   - Plan for existing table migration
   - Handle active games
   - Migrate player data

## 8. Testing Strategy

1. Unit Tests:
   - Individual contract testing
   - Interface compliance
   - Storage optimization

2. Integration Tests:
   - Cross-contract interactions
   - Frontend integration
   - Backend monitoring

3. Gas Optimization:
   - Function call costs
   - Storage operation costs
   - Event emission costs

## 9. Documentation Requirements

1. Technical Documentation:
   - Contract interfaces
   - Function specifications
   - Event definitions

2. Integration Documentation:
   - Frontend integration guide
   - Backend integration guide
   - Migration procedures

3. User Documentation:
   - Updated gameplay guide
   - Interface changes
   - New features/optimizations
