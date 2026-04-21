import { ethers } from 'ethers'

/**
 * Convert big number to readable format
 * Example: 1000000000000000000 → 1.00
 */
export function formatBalance(value: string | bigint, decimals = 18): string {
    if (!value) return '0.00'
    try {
        return parseFloat(
            ethers.formatUnits(value.toString(), decimals)
        ).toFixed(2)
    } catch {
        return '0.00'
    }
}

/**
 * Convert readable number to blockchain format
 * Example: 1.5 → 1500000000000000000
 */
export function parseAmount(amount: string, decimals = 18): string {
    if (!amount) return '0'
    try {
        return ethers.parseUnits(amount, decimals).toString()
    } catch {
        return '0'
    }
}

/**
 * Shorten wallet address
 * Example: 0x1234...5678
 */
export function shortenAddress(address: string): string {
    if (!address) return ''
    return `${address.slice(0, 6)}...${address.slice(-4)}`
}

/**
 * Format large numbers with commas
 * Example: 1000000 → 1,000,000
 */
export function formatNumber(num: number): string {
    return num.toLocaleString('en-US', {
        maximumFractionDigits: 2,
        minimumFractionDigits: 2,
    })
}