'use client'

import { useReadContract } from 'wagmi'
import { ADDRESSES, LENDING_POOL_ABI } from '@/lib/contracts'
import { formatBalance, formatNumber } from '@/lib/utils'

export default function PoolStats() {
    // Read pool stats from blockchain
    const { data: poolStats, isLoading } = useReadContract({
        address: ADDRESSES.lendingPool as `0x${string}`,
        abi: LENDING_POOL_ABI,
        functionName: 'getPoolStats',
    })

    if (isLoading) {
        return (
            <div className="text-white/60 py-8">Loading pool stats...</div>
        )
    }
    const profileconfig = poolStats as any[]
    const poolBalance = profileconfig?.[0] ? formatBalance(profileconfig[0]) : '0'
    const totalEarned = profileconfig?.[1] ? formatBalance(profileconfig[1]) : '0'
    const lenderCount = profileconfig?.[2] ? Number(profileconfig[2]) : 0
    const platformFees = profileconfig?.[3] ? formatBalance(profileconfig[3]) : '0'

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {/* Pool Balance */}
            <div className="bg-gradient-to-br from-blue-500/20 to-blue-600/20 rounded-lg p-6 border border-blue-500/30 hover:border-blue-500/50 transition">
                <p className="text-blue-300/80 text-sm mb-2">Pool Balance</p>
                <p className="text-3xl font-bold text-white">${poolBalance}</p>
                <p className="text-blue-300/60 text-xs mt-2">USDC Available</p>
            </div>

            {/* Total Interest Earned */}
            <div className="bg-gradient-to-br from-green-500/20 to-green-600/20 rounded-lg p-6 border border-green-500/30 hover:border-green-500/50 transition">
                <p className="text-green-300/80 text-sm mb-2">Total Interest Earned</p>
                <p className="text-3xl font-bold text-white">${totalEarned}</p>
                <p className="text-green-300/60 text-xs mt-2">By All Lenders</p>
            </div>

            {/* Lender Count */}
            <div className="bg-gradient-to-br from-purple-500/20 to-purple-600/20 rounded-lg p-6 border border-purple-500/30 hover:border-purple-500/50 transition">
                <p className="text-purple-300/80 text-sm mb-2">Active Lenders</p>
                <p className="text-3xl font-bold text-white">{lenderCount}</p>
                <p className="text-purple-300/60 text-xs mt-2">Earning Interest</p>
            </div>

            {/* Platform Fees */}
            <div className="bg-gradient-to-br from-pink-500/20 to-pink-600/20 rounded-lg p-6 border border-pink-500/30 hover:border-pink-500/50 transition">
                <p className="text-pink-300/80 text-sm mb-2">Platform Fees</p>
                <p className="text-3xl font-bold text-white">${platformFees}</p>
                <p className="text-pink-300/60 text-xs mt-2">Collected</p>
            </div>
        </div>
    )
}