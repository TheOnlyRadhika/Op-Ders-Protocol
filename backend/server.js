const express = require('express')
const cors = require('cors')
const bodyParser = require('body-parser')
const { ethers } = require('ethers')
require('dotenv').config()

const app = express()

// Middleware
app.use(cors({ origin: process.env.FRONTEND_URL }))
app.use(bodyParser.json())

// Setup blockchain connection
const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL)
const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider)

console.log(`✅ Connected to wallet: ${signer.address}`)

// ===== SIMPLE ABIS =====

const CREDIT_SCORING_ABI = [
    'function getCreditProfile(address user) view returns (uint256, uint256, uint256, uint256, uint256, uint256, bool, uint256)',
    'function canUserWriteOptions(address user) view returns (bool)',
    'function getCollateralizationRatio(address user) view returns (uint256)',
]

const LENDING_POOL_ABI = [
    'function getPoolStats() view returns (uint256, uint256, uint256, uint256)',
    'function getLenderStats(address lender) view returns (uint256, uint256, uint256, uint256)',
    'function getBorrowerStats(address borrower) view returns (uint256, uint256, uint256, uint256)',
    'function getMaxBorrowAmount(address borrower, uint256 collateral) view returns (uint256)',
]

const OPTIONS_ABI = [
    'function getOption(uint256 optionId) view returns (tuple(uint256, address, address, uint8, uint8, address, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool))',
    'function getUserWrittenOptions(address user) view returns (uint256[])',
    'function getUserBoughtOptions(address user) view returns (uint256[])',
    'function isOptionActive(uint256 optionId) view returns (bool)',
]

const USDC_ABI = [
    'function balanceOf(address account) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)',
    'function transfer(address to, uint256 amount) returns (bool)',
]

// ===== HEALTH CHECK =====

app.get('/api/health', (req, res) => {
    res.json({
        status: 'ok',
        message: 'Backend is running',
        timestamp: new Date().toISOString(),
    })
})

// ===== CREDIT SCORING ENDPOINTS =====

/**
 * GET /api/credit/:address
 * Get credit profile for a user
 */
app.get('/api/credit/:address', async (req, res) => {
    try {
        const { address } = req.params

        // Validate address
        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const creditScoring = new ethers.Contract(
            process.env.CREDIT_SCORING_ADDR,
            CREDIT_SCORING_ABI,
            provider
        )

        const profile = await creditScoring.getCreditProfile(address)

        res.json({
            address,
            creditScore: Number(profile[0]),
            totalBorrowed: ethers.formatUnits(profile[1], 18),
            totalRepaid: ethers.formatUnits(profile[2], 18),
            activeDebts: Number(profile[3]),
            defaultedDebts: Number(profile[4]),
            lastUpdated: Number(profile[5]),
            isLockedFromWriting: profile[6],
            lockedUntilTimestamp: Number(profile[7]),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * GET /api/credit/:address/can-write
 * Check if user can write options
 */
app.get('/api/credit/:address/can-write', async (req, res) => {
    try {
        const { address } = req.params

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const creditScoring = new ethers.Contract(
            process.env.CREDIT_SCORING_ADDR,
            CREDIT_SCORING_ABI,
            provider
        )

        const canWrite = await creditScoring.canUserWriteOptions(address)

        res.json({ address, canWrite })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * GET /api/credit/:address/collateral-ratio
 * Get collateralization ratio for user
 */
app.get('/api/credit/:address/collateral-ratio', async (req, res) => {
    try {
        const { address } = req.params

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const creditScoring = new ethers.Contract(
            process.env.CREDIT_SCORING_ADDR,
            CREDIT_SCORING_ABI,
            provider
        )

        const ratio = await creditScoring.getCollateralizationRatio(address)

        res.json({
            address,
            collateralizationRatio: Number(ratio),
            percentage: `${(Number(ratio) / 100).toFixed(2)}%`,
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

// ===== LENDING POOL ENDPOINTS =====

/**
 * GET /api/pool/stats
 * Get pool statistics
 */
app.get('/api/pool/stats', async (req, res) => {
    try {
        const lendingPool = new ethers.Contract(
            process.env.LENDING_POOL_ADDR,
            LENDING_POOL_ABI,
            provider
        )

        const stats = await lendingPool.getPoolStats()

        res.json({
            poolBalance: ethers.formatUnits(stats[0], 18),
            totalInterestEarned: ethers.formatUnits(stats[1], 18),
            numLenders: Number(stats[2]),
            platformFeeCollected: ethers.formatUnits(stats[3], 18),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * GET /api/pool/lender/:address
 * Get lender statistics
 */
app.get('/api/pool/lender/:address', async (req, res) => {
    try {
        const { address } = req.params

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const lendingPool = new ethers.Contract(
            process.env.LENDING_POOL_ADDR,
            LENDING_POOL_ABI,
            provider
        )

        const stats = await lendingPool.getLenderStats(address)

        res.json({
            address,
            depositAmount: ethers.formatUnits(stats[0], 18),
            depositTime: Number(stats[1]),
            interestEarned: ethers.formatUnits(stats[2], 18),
            maxWithdrawable: ethers.formatUnits(stats[3], 18),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * GET /api/pool/borrower/:address
 * Get borrower statistics
 */
app.get('/api/pool/borrower/:address', async (req, res) => {
    try {
        const { address } = req.params

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const lendingPool = new ethers.Contract(
            process.env.LENDING_POOL_ADDR,
            LENDING_POOL_ABI,
            provider
        )

        const stats = await lendingPool.getBorrowerStats(address)

        res.json({
            address,
            totalLoans: Number(stats[0]),
            collateralLocked: ethers.formatUnits(stats[1], 18),
            activeLoans: Number(stats[2]),
            repaidLoans: Number(stats[3]),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * GET /api/pool/max-borrow/:address/:collateral
 * Calculate max borrowable amount
 */
app.get('/api/pool/max-borrow/:address/:collateral', async (req, res) => {
    try {
        const { address, collateral } = req.params

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const lendingPool = new ethers.Contract(
            process.env.LENDING_POOL_ADDR,
            LENDING_POOL_ABI,
            provider
        )

        const collateralAmount = ethers.parseUnits(collateral, 18)
        const maxBorrow = await lendingPool.getMaxBorrowAmount(address, collateralAmount)

        res.json({
            address,
            collateralAmount: collateral,
            maxBorrowAmount: ethers.formatUnits(maxBorrow, 18),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

// ===== OPTIONS ENDPOINTS =====

/**
 * GET /api/options/:optionId
 * Get option details
 */
app.get('/api/options/:optionId', async (req, res) => {
    try {
        const { optionId } = req.params

        const options = new ethers.Contract(
            process.env.OPTIONS_ADDR,
            OPTIONS_ABI,
            provider
        )

        const option = await options.getOption(optionId)

        res.json({
            optionId,
            writer: option[1],
            buyer: option[2],
            optionType: option[3] === 0 ? 'CALL' : 'PUT',
            status: ['ACTIVE', 'EXERCISED', 'EXPIRED', 'CANCELLED'][option[4]],
            underlyingToken: option[5],
            strikePrice: ethers.formatUnits(option[6], 18),
            quantity: ethers.formatUnits(option[7], 18),
            premium: ethers.formatUnits(option[8], 18),
            createdAt: Number(option[13]),
            expiresAt: Number(option[14]),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * GET /api/options/user/:address/written
 * Get options written by user
 */
app.get('/api/options/user/:address/written', async (req, res) => {
    try {
        const { address } = req.params

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const options = new ethers.Contract(
            process.env.OPTIONS_ADDR,
            OPTIONS_ABI,
            provider
        )

        const writtenOptions = await options.getUserWrittenOptions(address)

        res.json({
            address,
            writtenOptions: writtenOptions.map((id) => Number(id)),
            count: writtenOptions.length,
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * GET /api/options/user/:address/bought
 * Get options bought by user
 */
app.get('/api/options/user/:address/bought', async (req, res) => {
    try {
        const { address } = req.params

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const options = new ethers.Contract(
            process.env.OPTIONS_ADDR,
            OPTIONS_ABI,
            provider
        )

        const boughtOptions = await options.getUserBoughtOptions(address)

        res.json({
            address,
            boughtOptions: boughtOptions.map((id) => Number(id)),
            count: boughtOptions.length,
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

// ===== UTILITY ENDPOINTS =====

/**
 * GET /api/user/:address/dashboard
 * Get all user data (comprehensive dashboard data)
 */
app.get('/api/user/:address/dashboard', async (req, res) => {
    try {
        const { address } = req.params

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const creditScoring = new ethers.Contract(
            process.env.CREDIT_SCORING_ADDR,
            CREDIT_SCORING_ABI,
            provider
        )
        const lendingPool = new ethers.Contract(
            process.env.LENDING_POOL_ADDR,
            LENDING_POOL_ABI,
            provider
        )
        const options = new ethers.Contract(
            process.env.OPTIONS_ADDR,
            OPTIONS_ABI,
            provider
        )

        // Fetch all data in parallel
        const [creditProfile, borrowerStats, lenderStats, writtenOpts, boughtOpts] =
            await Promise.all([
                creditScoring.getCreditProfile(address),
                lendingPool.getBorrowerStats(address),
                lendingPool.getLenderStats(address),
                options.getUserWrittenOptions(address),
                options.getUserBoughtOptions(address),
            ])

        res.json({
            address,
            creditProfile: {
                creditScore: Number(creditProfile[0]),
                totalBorrowed: ethers.formatUnits(creditProfile[1], 18),
                totalRepaid: ethers.formatUnits(creditProfile[2], 18),
                activeDebts: Number(creditProfile[3]),
                isLockedFromWriting: creditProfile[6],
            },
            borrowing: {
                totalLoans: Number(borrowerStats[0]),
                collateralLocked: ethers.formatUnits(borrowerStats[1], 18),
                activeLoans: Number(borrowerStats[2]),
                repaidLoans: Number(borrowerStats[3]),
            },
            lending: {
                depositAmount: ethers.formatUnits(lenderStats[0], 18),
                interestEarned: ethers.formatUnits(lenderStats[2], 18),
                maxWithdrawable: ethers.formatUnits(lenderStats[3], 18),
            },
            options: {
                writtenCount: writtenOpts.length,
                boughtCount: boughtOpts.length,
            },
            timestamp: new Date().toISOString(),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

// ===== TRANSACTION HISTORY =====

const { startEventListener, getUserTransactionHistory, getAllEvents } = require('./services/eventListener')

// Start event listeners
startEventListener()

/**
 * GET /api/transactions/:address
 * Get transaction history for a user
 */
app.get('/api/transactions/:address', (req, res) => {
    try {
        const { address } = req.params

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid Ethereum address' })
        }

        const history = getUserTransactionHistory(address)

        res.json({
            address,
            transactions: history,
            count: history.length,
            timestamp: new Date().toISOString(),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * GET /api/transactions
 * Get all transactions (global feed)
 */
app.get('/api/transactions', (req, res) => {
    try {
        const events = getAllEvents()

        res.json({
            transactions: events,
            count: events.length,
            timestamp: new Date().toISOString(),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

// ===== WRITE OPERATIONS HELPERS =====

/**
 * POST /api/estimate/write-call
 * Estimate collateral needed for writing a call
 */
app.post('/api/estimate/write-call', async (req, res) => {
    try {
        const { address, quantity, strikePrice } = req.body

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid address' })
        }

        const creditScoring = new ethers.Contract(
            process.env.CREDIT_SCORING_ADDR,
            CREDIT_SCORING_ABI,
            provider
        )

        const ratio = await creditScoring.getCollateralizationRatio(address)

        // For call: collateral = quantity
        const collateralNeeded = quantity
        const collateralToDeposit = (collateralNeeded * ratio) / 10000
        const creditBacked = collateralNeeded - collateralToDeposit

        res.json({
            quantity,
            strikePrice,
            collateralNeeded: ethers.formatUnits(collateralNeeded, 18),
            collateralToDeposit: ethers.formatUnits(collateralToDeposit, 18),
            creditBacked: ethers.formatUnits(creditBacked, 18),
            ratio: `${(Number(ratio) / 100).toFixed(2)}%`,
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * POST /api/estimate/write-put
 * Estimate collateral needed for writing a put
 */
app.post('/api/estimate/write-put', async (req, res) => {
    try {
        const { address, quantity, strikePrice } = req.body

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid address' })
        }

        const creditScoring = new ethers.Contract(
            process.env.CREDIT_SCORING_ADDR,
            CREDIT_SCORING_ABI,
            provider
        )

        const ratio = await creditScoring.getCollateralizationRatio(address)

        // For put: collateral = strike price × quantity
        const collateralNeeded = strikePrice * quantity
        const collateralToDeposit = (collateralNeeded * ratio) / 10000
        const creditBacked = collateralNeeded - collateralToDeposit

        res.json({
            quantity,
            strikePrice,
            collateralNeeded: ethers.formatUnits(collateralNeeded, 18),
            collateralToDeposit: ethers.formatUnits(collateralToDeposit, 18),
            creditBacked: ethers.formatUnits(creditBacked, 18),
            ratio: `${(Number(ratio) / 100).toFixed(2)}%`,
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

/**
 * POST /api/estimate/borrow
 * Estimate max borrowable amount
 */
app.post('/api/estimate/borrow', async (req, res) => {
    try {
        const { address, collateral } = req.body

        if (!ethers.isAddress(address)) {
            return res.status(400).json({ error: 'Invalid address' })
        }

        const creditScoring = new ethers.Contract(
            process.env.CREDIT_SCORING_ADDR,
            CREDIT_SCORING_ABI,
            provider
        )
        const lendingPool = new ethers.Contract(
            process.env.LENDING_POOL_ADDR,
            LENDING_POOL_ABI,
            provider
        )

        const [creditProfile, stats] = await Promise.all([
            creditScoring.getCreditProfile(address),
            lendingPool.getPoolStats(),
        ])

        const creditScore = Number(creditProfile[0])
        const ratio = await creditScoring.getCollateralizationRatio(address)
        const collateralAmount = ethers.parseUnits(collateral, 18)
        const maxBorrow = (collateralAmount * 10000n) / ratio

        // Get interest rate
        let interestRate = 12 // default
        if (creditScore >= 800) interestRate = 2
        else if (creditScore >= 600) interestRate = 5
        else if (creditScore >= 300) interestRate = 8

        // Calculate monthly interest
        const monthlyInterest = (Number(maxBorrow) * interestRate) / 12 / 100

        res.json({
            address,
            collateral,
            maxBorrowAmount: ethers.formatUnits(maxBorrow, 18),
            interestRate: `${interestRate}% APR`,
            monthlyInterest: ethers.formatUnits(monthlyInterest.toString(), 18),
            creditScore,
            poolAvailable: ethers.formatUnits(stats[0], 18),
        })
    } catch (error) {
        console.error('Error:', error)
        res.status(500).json({ error: error.message })
    }
})

// ===== ERROR HANDLING =====

app.use((err, req, res, next) => {
    console.error('Unhandled error:', err)
    res.status(500).json({ error: 'Internal server error' })
})

app.use((req, res) => {
    res.status(404).json({ error: 'Endpoint not found' })
})

// ===== START SERVER =====

const PORT = process.env.PORT || 3001

app.listen(PORT, () => {
    console.log(`
    ╔════════════════════════════════╗
    ║   OptionsCredit Backend v1.0   ║
    ╚════════════════════════════════╝
    
    🚀 Server running on http://localhost:${PORT}
    🔗 Blockchain: Sepolia Testnet
    ✅ Wallet connected: ${signer.address}
    
    📡 Available endpoints:
    GET  /api/health
    GET  /api/credit/:address
    GET  /api/pool/stats
    GET  /api/options/:optionId
    GET  /api/user/:address/dashboard
    
    📖 Full docs at http://localhost:${PORT}/api/docs (coming soon)
  `)
})

module.exports = app