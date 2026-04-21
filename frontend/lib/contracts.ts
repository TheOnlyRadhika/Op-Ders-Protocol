// This file contains your contract addresses and ABIs
// ABI = How to talk to contracts

export const ADDRESSES = {
    creditScoring: '0xAFE441db95Ab9B1889fF613B9B605Bc3C8Ee4d17', // Replace with your deployed address
    lendingPool: '0x2bB0A9806fE271613c47Bf1b240caad7eA8dc629',   // Replace with your deployed address
    options: '0x123cAF28b8fb08e03904A9641060B89110410B44',       // Replace with your deployed address
    usdc: '0x07865c6E87B9F70255377e024ace6630C1Eaa37F', // Sepolia USDC
}

// Simplified ABI (only functions we need)
export const USDC_ABI = [
    {
        name: 'approve',
        type: 'function',
        inputs: [
            { name: 'spender', type: 'address' },
            { name: 'amount', type: 'uint256' },
        ],
        outputs: [{ type: 'bool' }],
    },
    {
        name: 'balanceOf',
        type: 'function',
        inputs: [{ name: 'account', type: 'address' }],
        outputs: [{ type: 'uint256' }],
    },
]

export const CREDIT_SCORING_ABI = [
    {
        name: 'getCreditProfile',
        type: 'function',
        inputs: [{ name: '_user', type: 'address' }],
        outputs: [
            { name: 'creditScore', type: 'uint256' },
            { name: 'totalBorrowed', type: 'uint256' },
            { name: 'totalRepaid', type: 'uint256' },
            { name: 'activeDebts', type: 'uint256' },
            { name: 'defaultedDebts', type: 'uint256' },
            { name: 'lastUpdated', type: 'uint256' },
            { name: 'isLockedFromWriting', type: 'bool' },
            { name: 'lockedUntilTimestamp', type: 'uint256' },
        ],
    },
    {
        name: 'canUserWriteOptions',
        type: 'function',
        inputs: [{ name: '_user', type: 'address' }],
        outputs: [{ type: 'bool' }],
    },
]

export const LENDING_POOL_ABI = [
    {
        name: 'depositToPool',
        type: 'function',
        inputs: [{ name: '_amount', type: 'uint256' }],
        outputs: [],
    },
    {
        name: 'getPoolStats',
        type: 'function',
        inputs: [],
        outputs: [
            { name: 'currentBalance', type: 'uint256' },
            { name: 'totalEarned', type: 'uint256' },
            { name: 'numLenders', type: 'uint256' },
            { name: 'platformFees', type: 'uint256' },
        ],
    },
]

export const OPTIONS_ABI = [
    {
        name: 'writeCall',
        type: 'function',
        inputs: [
            { name: '_underlyingToken', type: 'address' },
            { name: '_strikePrice', type: 'uint256' },
            { name: '_quantity', type: 'uint256' },
            { name: '_premium', type: 'uint256' },
            { name: '_daysToExpiry', type: 'uint256' },
        ],
        outputs: [],
    },
]