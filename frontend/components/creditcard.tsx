'use client'

import { useAccount, useReadContract } from 'wagmi'
import { ADDRESSES, CREDIT_SCORING_ABI } from '@/lib/contracts'
import { formatBalance } from '@/lib/utils'

export default function CreditCard() {
    const { address, isConnected } = useAccount()

    // Read credit profile from blockchain
    const { data: creditProfile, isLoading } = useReadContract({
        address: ADDRESSES.creditScoring as `0x${string}`,
        abi: CREDIT_SCORING_ABI,
        functionName: 'getCreditProfile',
        args: [address as `0x${string}`],
        query: { enabled: !!address },
    })

    if (!isConnected) {
        return (
            <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
                <p className="text-white/60">Connect wallet to see your credit profile</p>
            </div>
        )
    }

    if (isLoading) {
        return (
            <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
                <p className="text-white/60">Loading...</p>
            </div>
        )
    }
    const profile = creditProfile as any[]
    // Extract data from blockchain response
    const creditScore = profile?.[0] ? Number(profile[0]) : 0
    const totalBorrowed = profile?.[1] ? formatBalance(profile[1]) : '0'
    const totalRepaid = profile?.[2] ? formatBalance(profile[2]) : '0'
    const activeDebts = profile?.[3] ? Number(profile[3]) : 0

    // Determine credit tier
    let tier = 'No Credit'
    let tierColor = 'from-gray-400 to-gray-600'

    if (creditScore >= 800) {
        tier = 'Excellent'
        tierColor = 'from-green-400 to-emerald-600'
    } else if (creditScore >= 600) {
        tier = 'Good'
        tierColor = 'from-blue-400 to-cyan-600'
    } else if (creditScore >= 300) {
        tier = 'Fair'
        tierColor = 'from-yellow-400 to-orange-600'
    }

    return (
        <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-8 border border-white/10 hover:border-white/20 transition">
            <h2 className="text-xl font-bold text-white mb-6">Your Credit Profile</h2>

            {/* Credit Score */}
            <div className="mb-8">
                <div className={`bg-gradient-to-r ${tierColor} rounded-lg p-6`}>
                    <p className="text-white/80 text-sm mb-2">Credit Score</p>
                    <div className="flex items-end gap-2">
                        <span className="text-5xl font-bold text-white">{creditScore}</span>
                        <span className="text-white/60 mb-2">/1000</span>
                    </div>
                    <p className="text-white mt-2">{tier} Credit</p>
                </div>
            </div>

            {/* Stats Grid */}
            <div className="grid grid-cols-2 gap-4">
                <div className="bg-white/5 rounded-lg p-4">
                    <p className="text-white/60 text-sm mb-2">Total Borrowed</p>
                    <p className="text-2xl font-bold text-white">${totalBorrowed}</p>
                </div>
                <div className="bg-white/5 rounded-lg p-4">
                    <p className="text-white/60 text-sm mb-2">Total Repaid</p>
                    <p className="text-2xl font-bold text-white">${totalRepaid}</p>
                </div>
                <div className="bg-white/5 rounded-lg p-4">
                    <p className="text-white/60 text-sm mb-2">Active Debts</p>
                    <p className="text-2xl font-bold text-white">{activeDebts}</p>
                </div>
                <div className="bg-white/5 rounded-lg p-4">
                    <p className="text-white/60 text-sm mb-2">Leverage Available</p>
                    <p className="text-2xl font-bold text-white">
                        {creditScore >= 800 ? '4x' : creditScore >= 600 ? '2x' : '1x'}
                    </p>
                </div>
            </div>
        </div>
    )
}