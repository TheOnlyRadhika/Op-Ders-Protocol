'use client'

import { useAccount, useWriteContract } from 'wagmi'
import { useState } from 'react'
import { ADDRESSES, USDC_ABI, OPTIONS_ABI } from '@/lib/contracts'
import { parseAmount } from '@/lib/utils'
import api from '@/lib/api'

export default function WriteOptionsForm() {
    const { address, isConnected } = useAccount()
    const { writeContractAsync } = useWriteContract()

    const [optionType, setOptionType] = useState<'CALL' | 'PUT'>('CALL')
    const [strikePrice, setStrikePrice] = useState('')
    const [quantity, setQuantity] = useState('')
    const [premium, setPremium] = useState('')
    const [daysToExpiry, setDaysToExpiry] = useState('30')

    const [estimate, setEstimate] = useState<any>(null)
    const [isLoading, setIsLoading] = useState(false)
    const [error, setError] = useState('')
    const [success, setSuccess] = useState('')

    // Get collateral estimate
    const handleEstimate = async () => {
        if (!address || !strikePrice || !quantity) {
            setError('Please fill all fields')
            return
        }

        try {
            setIsLoading(true)
            setError('')

            const endpoint = optionType === 'CALL' ? '/api/estimate/write-call' : '/api/estimate/write-put'

            const response = await api.post(endpoint, {
                address,
                quantity: parseAmount(quantity),
                strikePrice: parseAmount(strikePrice),
            })

            setEstimate(response.data)
        } catch (err: any) {
            setError(err.message || 'Failed to estimate')
        } finally {
            setIsLoading(false)
        }
    }

    // Write option
    const handleWriteOption = async () => {
        if (!address || !strikePrice || !quantity || !premium || !daysToExpiry) {
            setError('Please fill all fields')
            return
        }

        try {
            setIsLoading(true)
            setError('')
            setSuccess('')

            // Step 1: Approve USDC
            const collateralAmount = estimate?.collateralToDeposit
                ? parseAmount(estimate.collateralToDeposit)
                : parseAmount(quantity)

            console.log('Approving USDC...')
            await writeContractAsync({
                address: ADDRESSES.usdc as `0x${string}`,
                abi: USDC_ABI,
                functionName: 'approve',
                args: [ADDRESSES.options as `0x${string}`, BigInt(collateralAmount)],
            })

            // Step 2: Write option
            console.log(`Writing ${optionType} option...`)
            await writeContractAsync({
                address: ADDRESSES.options as `0x${string}`,
                abi: OPTIONS_ABI,
                functionName: optionType === 'CALL' ? 'writeCall' : 'writePut',
                args: [
                    ADDRESSES.usdc,
                    BigInt(parseAmount(strikePrice)),
                    BigInt(parseAmount(quantity)),
                    BigInt(parseAmount(premium)),
                    BigInt(daysToExpiry),
                ],
            })

            setSuccess(`✅ ${optionType} option created successfully!`)
            setStrikePrice('')
            setQuantity('')
            setPremium('')
            setEstimate(null)
        } catch (err: any) {
            setError(err.message || `Failed to write ${optionType} option`)
        } finally {
            setIsLoading(false)
        }
    }

    if (!isConnected) {
        return (
            <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
                <p className="text-white/60">Connect wallet to write options</p>
            </div>
        )
    }

    return (
        <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
            <h3 className="text-lg font-bold text-white mb-4">Write Options</h3>

            {/* Option Type Selector */}
            <div className="flex gap-2 mb-6">
                <button
                    onClick={() => setOptionType('CALL')}
                    className={`flex-1 py-2 px-4 rounded-lg font-bold transition ${optionType === 'CALL'
                            ? 'bg-green-500/30 border border-green-500 text-green-300'
                            : 'bg-white/10 border border-white/20 text-white hover:bg-white/20'
                        }`}
                >
                    Call Option 📈
                </button>
                <button
                    onClick={() => setOptionType('PUT')}
                    className={`flex-1 py-2 px-4 rounded-lg font-bold transition ${optionType === 'PUT'
                            ? 'bg-red-500/30 border border-red-500 text-red-300'
                            : 'bg-white/10 border border-white/20 text-white hover:bg-white/20'
                        }`}
                >
                    Put Option 📉
                </button>
            </div>

            {/* Form Fields */}
            <div className="space-y-4 mb-6">
                <div>
                    <label className="block text-white/80 text-sm mb-2">Strike Price (USDC)</label>
                    <input
                        type="number"
                        placeholder="e.g., 3500"
                        value={strikePrice}
                        onChange={(e) => setStrikePrice(e.target.value)}
                        className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-white/40 focus:outline-none focus:border-purple-500"
                    />
                </div>

                <div>
                    <label className="block text-white/80 text-sm mb-2">Quantity</label>
                    <input
                        type="number"
                        placeholder="e.g., 10"
                        value={quantity}
                        onChange={(e) => setQuantity(e.target.value)}
                        className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-white/40 focus:outline-none focus:border-purple-500"
                    />
                </div>

                <div>
                    <label className="block text-white/80 text-sm mb-2">Premium (USDC)</label>
                    <input
                        type="number"
                        placeholder="e.g., 500"
                        value={premium}
                        onChange={(e) => setPremium(e.target.value)}
                        className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-white/40 focus:outline-none focus:border-purple-500"
                    />
                </div>

                <div>
                    <label className="block text-white/80 text-sm mb-2">Days to Expiry</label>
                    <input
                        type="number"
                        placeholder="e.g., 30"
                        value={daysToExpiry}
                        onChange={(e) => setDaysToExpiry(e.target.value)}
                        className="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-white/40 focus:outline-none focus:border-purple-500"
                    />
                </div>
            </div>

            {/* Estimate Section */}
            {estimate && (
                <div className="bg-white/5 rounded-lg p-4 mb-6 border border-purple-500/30">
                    <h4 className="text-white font-bold mb-3">Collateral Estimate</h4>
                    <div className="grid grid-cols-2 gap-3">
                        <div>
                            <p className="text-white/60 text-sm">Collateral Needed</p>
                            <p className="text-white font-bold">${estimate.collateralNeeded}</p>
                        </div>
                        <div>
                            <p className="text-white/60 text-sm">You Deposit</p>
                            <p className="text-green-400 font-bold">${estimate.collateralToDeposit}</p>
                        </div>
                        <div>
                            <p className="text-white/60 text-sm">Credit-Backed</p>
                            <p className="text-purple-400 font-bold">${estimate.creditBacked}</p>
                        </div>
                        <div>
                            <p className="text-white/60 text-sm">Your Ratio</p>
                            <p className="text-blue-400 font-bold">{estimate.ratio}</p>
                        </div>
                    </div>
                </div>
            )}

            {/* Buttons */}
            <div className="flex gap-3">
                <button
                    onClick={handleEstimate}
                    disabled={isLoading || !strikePrice || !quantity}
                    className="flex-1 px-4 py-2 bg-blue-500/30 hover:bg-blue-500/50 disabled:bg-gray-500/30 border border-blue-500/50 rounded-lg text-white font-bold transition disabled:cursor-not-allowed"
                >
                    {isLoading ? '⏳ Estimating...' : '📊 Estimate'}
                </button>
                <button
                    onClick={handleWriteOption}
                    disabled={isLoading || !estimate}
                    className="flex-1 px-4 py-2 bg-gradient-to-r from-purple-500 to-pink-500 hover:from-purple-600 hover:to-pink-600 disabled:from-gray-500 disabled:to-gray-500 rounded-lg text-white font-bold transition disabled:cursor-not-allowed"
                >
                    {isLoading ? '⏳ Writing...' : 'Write Option'}
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