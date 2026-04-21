const { ethers } = require('ethers')
require('dotenv').config()

const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL)

// Simple in-memory storage (replace with database later)
const transactionHistory = {}
const eventLog = []

const OPTIONS_ABI = [
    'event OptionCreated(uint256 indexed optionId, address indexed writer, uint8 optionType, uint256 strikePrice, uint256 quantity, uint256 premium, uint256 expiresAt)',
    'event OptionBought(uint256 indexed optionId, address indexed buyer, uint256 premiumPaid)',
    'event OptionExercised(uint256 indexed optionId, address indexed buyer, uint256 exercisedAt)',
    'event OptionExpired(uint256 indexed optionId, address indexed writer)',
]

const LENDING_POOL_ABI = [
    'event DepositedToPool(address indexed lender, uint256 amount)',
    'event LoanCreated(address indexed borrower, uint256 indexed loanId, uint256 principal, uint256 collateral, uint256 interestRate, uint256 deadline)',
    'event LoanFullyRepaid(address indexed borrower, uint256 indexed loanId, uint256 totalRepaid, uint256 interestPaid)',
    'event LoanDefaulted(address indexed borrower, uint256 indexed loanId)',
]

/**
 * Initialize event listeners
 */
async function startEventListener() {
    try {
        console.log('🎧 Starting event listeners...')

        const optionsContract = new ethers.Contract(
            process.env.OPTIONS_ADDR,
            OPTIONS_ABI,
            provider
        )

        const lendingPoolContract = new ethers.Contract(
            process.env.LENDING_POOL_ADDR,
            LENDING_POOL_ABI,
            provider
        )

        // Listen to Option Events
        optionsContract.on('OptionCreated', (optionId, writer, optionType, strikePrice, quantity, premium, expiresAt, event) => {
            const log = {
                type: 'OptionCreated',
                optionId: Number(optionId),
                writer,
                optionType: optionType === 0 ? 'CALL' : 'PUT',
                strikePrice: ethers.formatUnits(strikePrice, 18),
                quantity: ethers.formatUnits(quantity, 18),
                premium: ethers.formatUnits(premium, 18),
                timestamp: new Date().toISOString(),
                txHash: event.transactionHash,
            }

            eventLog.push(log)
            if (!transactionHistory[writer]) transactionHistory[writer] = []
            transactionHistory[writer].push(log)

            console.log('✅ Option Created:', optionId)
        })

        optionsContract.on('OptionBought', (optionId, buyer, premiumPaid, event) => {
            const log = {
                type: 'OptionBought',
                optionId: Number(optionId),
                buyer,
                premiumPaid: ethers.formatUnits(premiumPaid, 18),
                timestamp: new Date().toISOString(),
                txHash: event.transactionHash,
            }

            eventLog.push(log)
            if (!transactionHistory[buyer]) transactionHistory[buyer] = []
            transactionHistory[buyer].push(log)

            console.log('✅ Option Bought:', optionId)
        })

        optionsContract.on('OptionExercised', (optionId, buyer, exercisedAt, event) => {
            const log = {
                type: 'OptionExercised',
                optionId: Number(optionId),
                buyer,
                exercisedAt: Number(exercisedAt),
                timestamp: new Date().toISOString(),
                txHash: event.transactionHash,
            }

            eventLog.push(log)
            if (!transactionHistory[buyer]) transactionHistory[buyer] = []
            transactionHistory[buyer].push(log)

            console.log('✅ Option Exercised:', optionId)
        })

        optionsContract.on('OptionExpired', (optionId, writer, event) => {
            const log = {
                type: 'OptionExpired',
                optionId: Number(optionId),
                writer,
                timestamp: new Date().toISOString(),
                txHash: event.transactionHash,
            }

            eventLog.push(log)
            if (!transactionHistory[writer]) transactionHistory[writer] = []
            transactionHistory[writer].push(log)

            console.log('✅ Option Expired:', optionId)
        })

        // Listen to Lending Pool Events
        lendingPoolContract.on('DepositedToPool', (lender, amount, event) => {
            const log = {
                type: 'Deposit',
                lender,
                amount: ethers.formatUnits(amount, 18),
                timestamp: new Date().toISOString(),
                txHash: event.transactionHash,
            }

            eventLog.push(log)
            if (!transactionHistory[lender]) transactionHistory[lender] = []
            transactionHistory[lender].push(log)

            console.log('✅ Deposit:', amount)
        })

        lendingPoolContract.on('LoanCreated', (borrower, loanId, principal, collateral, interestRate, deadline, event) => {
            const log = {
                type: 'LoanCreated',
                borrower,
                loanId: Number(loanId),
                principal: ethers.formatUnits(principal, 18),
                collateral: ethers.formatUnits(collateral, 18),
                interestRate: Number(interestRate),
                deadline: Number(deadline),
                timestamp: new Date().toISOString(),
                txHash: event.transactionHash,
            }

            eventLog.push(log)
            if (!transactionHistory[borrower]) transactionHistory[borrower] = []
            transactionHistory[borrower].push(log)

            console.log('✅ Loan Created:', loanId)
        })

        lendingPoolContract.on('LoanFullyRepaid', (borrower, loanId, totalRepaid, interestPaid, event) => {
            const log = {
                type: 'LoanRepaid',
                borrower,
                loanId: Number(loanId),
                totalRepaid: ethers.formatUnits(totalRepaid, 18),
                interestPaid: ethers.formatUnits(interestPaid, 18),
                timestamp: new Date().toISOString(),
                txHash: event.transactionHash,
            }

            eventLog.push(log)
            if (!transactionHistory[borrower]) transactionHistory[borrower] = []
            transactionHistory[borrower].push(log)

            console.log('✅ Loan Repaid:', loanId)
        })

        lendingPoolContract.on('LoanDefaulted', (borrower, loanId, event) => {
            const log = {
                type: 'LoanDefaulted',
                borrower,
                loanId: Number(loanId),
                timestamp: new Date().toISOString(),
                txHash: event.transactionHash,
            }

            eventLog.push(log)
            if (!transactionHistory[borrower]) transactionHistory[borrower] = []
            transactionHistory[borrower].push(log)

            console.log('⚠️ Loan Defaulted:', loanId)
        })

        console.log('✅ Event listeners started!')
    } catch (error) {
        console.error('Error starting event listeners:', error)
    }
}

/**
 * Get transaction history for a user
 */
function getUserTransactionHistory(address) {
    return transactionHistory[address] || []
}

/**
 * Get all events
 */
function getAllEvents() {
    return eventLog
}

module.exports = {
    startEventListener,
    getUserTransactionHistory,
    getAllEvents,
}