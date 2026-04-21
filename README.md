# Credit-Backed Options Protocol

A decentralized options trading protocol with integrated credit scoring and under-collateralized lending. Users can write options with reduced collateral requirements based on their creditworthiness, enabling more capital-efficient trading.

## 🎯 Problem Statement

Traditional options markets require **100% collateral upfront**, limiting access and capital efficiency:
- High collateral requirements lock up capital
- Creditworthy traders cannot leverage their track record
- No incentive mechanism for responsible borrowing behavior
- Market inefficiencies due to inflexible collateral requirements

**Our Solution:** A credit-score-backed system that:
- Allows under-collateralized options based on credit history
- Dynamically adjusts collateral requirements (25%-100%) based on creditworthiness
- Tracks lending and repaying behavior to build verifiable on-chain credit
- Integrates lending pools for missing collateral (credit-backed borrowing)

---

##  Protocol Architecture

### System Components
```
┌────────────────────────────────────────────────────────────────┐
│                        User / Frontend                         │
└──────────────┬─────────────────────────────────┬──────────────┘
               │                                 │
               ▼                                 ▼
   ┌───────────────────────┐         ┌───────────────────────┐
   │      LendingPool      │◄───────►│       Options         │
   │  - Deposit / Borrow   │         │  - Write Calls / Puts │
   │  - Collateral Loans   │         │  - Buy / Exercise     │
   │  - Default Handling   │         │  - Credit-Backed Opts │
   └──────────┬────────────┘         └───────────┬───────────┘
              │                                   │
              └──────────────┬────────────────────┘
                             │
                             ▼
                ┌────────────────────────┐
                │      CreditScoring     │
                │  - Credit Profiles     │
                │  - Debt Records        │
                │  - Score Updates       │
                └────────────────────────┘
```
 
All credit state lives in `CreditScoring`. Both `LendingPool` and `Options` call into it to create debts and record repayments. The score computed there feeds back into both contracts to determine collateral ratios and interest rates.
 
---
## Credit Score System
 
The credit score (0–1000) is the backbone of the protocol. Here is a summary of thresholds and their impact across all contracts:
 
```
Score 0 – 299   → Cannot borrow or write options
Score 300 – 599 → 100% collateral ratio, 8% APR, $5,000 max call notional
Score 600 – 799 → 50% collateral ratio, 5% APR, unlimited call notional
Score 800 – 1000 → 25% collateral ratio, 2% APR, unlimited call notional
```
 
New users start at 300 (base score) on their first borrow. Scores are capped at 1000 and floored at 0.
 
A user who defaults is **permanently locked** from writing options (`lockedUntilTimestamp = type(uint256).max`) until the owner manually intervenes.
 
---
## Getting Started
 
### Prerequisites
 
- Node.js ≥ 18
- Solidity ^0.8.20
- OpenZeppelin Contracts
- ERC-20 stablecoin (USDC, USDT, DAI)
- ERC-20 underlying token (WETH, etc.)
  
 ### Installation
 
```bash
git clone https://github.com/TheOnlyRadhika/Op-Ders-Protocol.git
cd OpDer-protocol
npm install
```
 
### Deployment Order
 
The contracts have dependencies — deploy in this exact order:
 
```
1. CreditScoring
2. LendingPool  (needs CreditScoring address + stablecoin address)
3. Options      (needs CreditScoring + LendingPool + underlyingToken + stablecoin addresses)
```

## 🚀 Running Both Frontend & Backend Together

### Option 1: Separate Terminal Windows

**Terminal 1 - Backend**

```bash
cd backend
npm run dev
```
Server running on http://localhost:5000

** Terminal 2 - Frontend
```bash
cd frontend
npm run dev
```
App running on http://localhost:3000

### Option 2: Option 2: Using concurrently (Recommended)

Install concurrently in root directory:
```bash
npm install concurrently
```
Add to root package.json:
```bash
{
  "scripts": {
    "dev": "concurrently \"npm run dev:backend\" \"npm run dev:frontend\"",
    "dev:backend": "cd backend && npm run dev",
    "dev:frontend": "cd frontend && npm start"
  }
}
```
Then run both together:
```bash
npm run dev
```
