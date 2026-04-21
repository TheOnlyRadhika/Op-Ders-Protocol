'use client'

import { useAccount, useWriteContract } from 'wagmi'
import { useState } from 'react'
import { ADDRESSES, USDC_ABI, LENDING_POOL_ABI } from '@/lib/contracts'
import { parseAmount, formatBalance } from '@/lib/utils'
import api from '@/lib/api'

export default function BorrowForm() {
    const { address, isConnected } = useAccount()
    const { writeContractAsync } = useWriteContract()

    const [collateral, setCollateral] = useState('')
    const [durationDays, setDurationDays] = useState('30')

    const [estimate, setEstimate] = useState<any>(null)
    const [isLoading, setIsLoading] = useState(false)
    const [error, setError] = useState('')
    const [success, setSuccess] = useState('')

    // Get borrow estimate
    const handleEstimate = async () => {
        if (!address || !collateral) {
            setError('Please enter collateral amount')
            return
        }

        try {
            setIsLoading(true)
            setError('')

            const response = await api.post('/api/estimate/borrow', {
                address,
                collateral,
            })

            setEstimate(response.data)
        } catch (err: any) {
            setError(err.message || 'Failed to estimate')
        } finally {
            setIsLoading(false)
        }
    }

    // Borrow
    const handleBorrow = async () => {
        if (!address || !collateral || !durationDays || !estimate) {
            setError('Please fill all fields')
            return
        }

        try {
            setIsLoading(true)
            setError('')
            setSuccess('')

            const collateralAmount = parseAmount(collateral)

            console.log('Approving USDC for collateral...')
            await writeContractAsync({
                address: ADDRESSES.usdc as `0x${string}`,
                abi: USDC_ABI,
                functionName: 'approve',
                args: [ADDRESSES.lendingPool as `0x${string}`, BigInt(collateralAmount)],
            })

            console.log('Borrowing...')
            await writeContractAsync({
                address: ADDRESSES.lendingPool as `0x${string}`,
                abi: LENDING_POOL_ABI,
                functionName: 'borrowWithCollateral',
                args: [BigInt(collateralAmount), BigInt(durationDays)],
            })

            setSuccess('✅ Loan created successfully!')
            setCollateral('')
            setEstimate(null)
        } catch (err: any) {
            setError(err.message || 'Failed to borrow')
        } finally {
            setIsLoading(false)
        }
    }

    if (!isConnected) {
        return (
            <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
                <p className="text-white/60">Connect wallet to borrow</p>
            </div>
        )
    }

    return (
        <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
            <h3 className="text-lg font-bold text-white mb-4">Borrow from Pool</h3>
            <p className="text-white/60 text-sm mb-4">Borrow up to 4x your collateral based on credit score</p>

            {/* Form */}
            <div className="space-y-4 mb-6">
                <div>
                    <label className="block text-white/80 text-sm mb-2">Collateral Amount (USDC)</label>
                    <input
                        type="number"
                        placeholder="e.g., 5000"
                        value={collateral}
                        onChange={(e) => setCollateral(e.target.value)}
                        className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-white/40 focus:outline-none focus:border-purple-500"
                    />
                    <p className="text-white/40 text-xs mt-1">💡 Tip: Higher credit score = less collateral needed</p>
                </div>

                <div>
                    <label className="block text-white/80 text-sm mb-2">Loan Duration (Days)</label>
                    <input
                        type="number"
                        placeholder="e.g., 30"
                        value={durationDays}
                        onChange={(e) => setDurationDays(e.target.value)}
                        className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-white/40 focus:outline-none focus:border-purple-500"
                    />
                </div>
            </div>

            {/* Estimate */}
            {estimate && (
                <div className="bg-white/5 rounded-lg p-4 mb-6 border border-blue-500/30">
                    <h4 className="text-white font-bold mb-3">Loan Estimate</h4>
                    <div className="grid grid-cols-2 gap-3">
                        <div>
                            <p className="text-white/60 text-sm">Credit Score</p>
                            <p className="text-white font-bold">{estimate.creditScore}</p>
                        </div>
                        <div>
                            <p className="text-white/60 text-sm">Interest Rate</p>
                            <p className="text-green-400 font-bold">{estimate.interestRate}</p>
                        </div>
                        <div>
                            <p className="text-white/60 text-sm">Max Borrow</p>
                            <p className="text-blue-400 font-bold">${estimate.maxBorrowAmount}</p>
                        </div>
                        <div>
                            <p className="text-white/60 text-sm">Monthly Interest</p>
                            <p className="text-orange-400 font-bold">${estimate.monthlyInterest}</p>
                        </div>
                    </div>
                    <p className="text-white/60 text-xs mt-3">
                        Pool has ${estimate.poolAvailable} USDC available
                    </p>
                </div>
            )}

            {/* Buttons */}
            <div className="flex gap-3">
                <button
                    onClick={handleEstimate}
                    disabled={isLoading || !collateral}
                    className="flex-1 px-4 py-2 bg-blue-500/30 hover:bg-blue-500/50 disabled:bg-gray-500/30 border border-blue-500/50 rounded-lg text-white font-bold transition disabled:cursor-not-allowed"
                >
                    {isLoading ? '⏳ Estimating...' : '📊 Estimate'}
                </button>
                <button
                    onClick={handleBorrow}
                    disabled={isLoading || !estimate}
                    className="flex-1 px-4 py-2 bg-gradient-to-r from-green-500 to-emerald-500 hover:from-green-600 hover:to-emerald-600 disabled:from-gray-500 disabled:to-gray-500 rounded-lg text-white font-bold transition disabled:cursor-not-allowed"
                >
                    {isLoading ? '⏳ Borrowing...' : 'Borrow Now'}
                </button>
            </div>

            {/* Messages */}
            {error && (
                <div className="mt-4 p-3 bg-red-500/20 border border-red-500/50 rounded-lg text-red-300 text-sm">
                    ❌ {error}
                </div>
            )}
            {success && (
                <div className="mt-4 p-3 bg-green-500/20 border border-green-500/50 rounded-lg text-green-300 text-sm">
                    {success}
                </div>
            )}
        </div>
    )
}