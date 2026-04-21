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

## 🏗️ Protocol Architecture

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
  
 ### Installation
 
```bash
git clone https://github.com/your-username/defi-credit-protocol.git
cd defi-credit-protocol
npm install
```
 
### Deployment Order
 
The contracts have dependencies — deploy in this exact order:
 
```
1. CreditScoring
2. LendingPool  (needs CreditScoring address + stablecoin address)
3. Options      (needs CreditScoring + LendingPool + underlyingToken + stablecoin addresses)
```


