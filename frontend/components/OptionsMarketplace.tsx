'use client'

import { useAccount, useWriteContract } from 'wagmi'
import { useState, useEffect } from 'react'
import { ADDRESSES, OPTIONS_ABI, USDC_ABI } from '@/lib/contracts'
import { parseAmount, formatBalance } from '@/lib/utils'
import api from '@/lib/api'

export default function OptionsMarketplace() {
    const { address, isConnected } = useAccount()
    const { writeContractAsync } = useWriteContract()

    const [writtenOptions, setWrittenOptions] = useState<any[]>([])
    const [boughtOptions, setBoughtOptions] = useState<any[]>([])
    const [activeTab, setActiveTab] = useState<'written' | 'bought'>('written')
    const [isLoading, setIsLoading] = useState(false)
    const [error, setError] = useState('')
    const [success, setSuccess] = useState('')

    // Fetch options
    useEffect(() => {
        if (!address) return

        const fetchOptions = async () => {
            try {
                setIsLoading(true)

                const [written, bought] = await Promise.all([
                    api.get(`/options/user/${address}/written`),
                    api.get(`/options/user/${address}/bought`),
                ])

                setWrittenOptions(written.data.writtenOptions || [])
                setBoughtOptions(bought.data.boughtOptions || [])
            } catch (err) {
                console.error('Error fetching options:', err)
            } finally {
                setIsLoading(false)
            }
        }

        fetchOptions()
    }, [address])

    const handleExercise = async (optionId: number) => {
        try {
            setIsLoading(true)
            setError('')
            setSuccess('')

            const option = await api.get(`/options/${optionId}`)
            const optionData = option.data

            // Calculate payment needed
            const payment = BigInt(optionData.strikePrice) * BigInt(optionData.quantity)

            // Approve USDC
            console.log('Approving USDC for exercise...')
            await writeContractAsync({
                address: ADDRESSES.usdc as `0x${string}`,
                abi: USDC_ABI,
                functionName: 'approve',
                args: [ADDRESSES.options as `0x${string}`, payment],
            })

            // Exercise
            console.log('Exercising option...')
            await writeContractAsync({
                address: ADDRESSES.options as `0x${string}`,
                abi: OPTIONS_ABI,
                functionName: optionData.optionType === 'CALL' ? 'exerciseCall' : 'exercisePut',
                args: [BigInt(optionId)],
            })

            setSuccess('✅ Option exercised successfully!')
        } catch (err: any) {
            setError(err.message || 'Failed to exercise option')
        } finally {
            setIsLoading(false)
        }
    }

    if (!isConnected) {
        return (
            <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
                <p className="text-white/60">Connect wallet to view options</p>
            </div>
        )
    }

    return (
        <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
            <h3 className="text-lg font-bold text-white mb-4">My Options</h3>

            {/* Tabs */}
            <div className="flex gap-2 mb-6">
                <button
                    onClick={() => setActiveTab('written')}
                    className={`px-4 py-2 rounded-lg font-bold transition ${activeTab === 'written'
                            ? 'bg-purple-500/30 border border-purple-500 text-purple-300'
                            : 'bg-white/10 border border-white/20 text-white hover:bg-white/20'
                        }`}
                >
                    Written ({writtenOptions.length})
                </button>
                <button
                    onClick={() => setActiveTab('bought')}
                    className={`px-4 py-2 rounded-lg font-bold transition ${activeTab === 'bought'
                            ? 'bg-purple-500/30 border border-purple-500 text-purple-300'
                            : 'bg-white/10 border border-white/20 text-white hover:bg-white/20'
                        }`}
                >
                    Bought ({boughtOptions.length})
                </button>
            </div>

            {/* Options List */}
            <div className="space-y-3">
                {isLoading ? (
                    <p className="text-white/60">Loading...</p>
                ) : activeTab === 'written' && writtenOptions.length === 0 ? (
                    <p className="text-white/60">No written options yet</p>
                ) : activeTab === 'bought' && boughtOptions.length === 0 ? (
                    <p className="text-white/60">No bought options yet</p>
                ) : (
                    (activeTab === 'written' ? writtenOptions : boughtOptions).map((optionId) => (
                        <OptionCard
                            key={optionId}
                            optionId={optionId}
                            onExercise={() => handleExercise(optionId)}
                            isLoading={isLoading}
                        />
                    ))
                )}
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

// Option Card Component
function OptionCard({
    optionId,
    onExercise,
    isLoading,
}: {
    optionId: number
    onExercise: () => void
    isLoading: boolean
}) {
    const [option, setOption] = useState<any>(null)
    const [isActive, setIsActive] = useState(true)

    useEffect(() => {
        const fetchOption = async () => {
            try {
                const response = await api.get(`/options/${optionId}`)
                setOption(response.data)
                setIsActive(response.data.status === 'ACTIVE')
            } catch (error) {
                console.error('Error fetching option:', error)
            }
        }

        fetchOption()
    }, [optionId])

    if (!option) {
        return <div className="text-white/60 text-sm">Loading option #{optionId}...</div>
    }

    return (
        <div className="bg-white/5 hover:bg-white/10 rounded-lg p-4 border border-white/10 transition">
            <div className="flex justify-between items-start mb-3">
                <div>
                    <div className="flex gap-2 items-center mb-2">
                        <span className={`text-sm font-bold px-2 py-1 rounded ${option.optionType === 'CALL'
                                ? 'bg-green-500/30 text-green-300'
                                : 'bg-red-500/30 text-red-300'
                            }`}>
                            {option.optionType}
                        </span>
                        <span className={`text-sm px-2 py-1 rounded ${option.status === 'ACTIVE'
                                ? 'bg-blue-500/30 text-blue-300'
                                : 'bg-gray-500/30 text-gray-300'
                            }`}>
                            {option.status}
                        </span>
                    </div>
                    <p className="text-white font-bold">
                        #{optionId} @ ${parseFloat(option.strikePrice).toFixed(2)}
                    </p>
                    <p className="text-white/60 text-sm">
                        {option.quantity} units • Premium: ${parseFloat(option.premium).toFixed(2)}
                    </p>
                </div>

                {isActive && (
                    <button
                        onClick={onExercise}
                        disabled={isLoading}
                        className="px-4 py-2 bg-gradient-to-r from-purple-500 to-pink-500 hover:from-purple-600 hover:to-pink-600 disabled:from-gray-500 disabled:to-gray-500 rounded-lg text-white font-bold text-sm transition disabled:cursor-not-allowed"
                    >
                        {isLoading ? 'Processing...' : 'Exercise'}
                    </button>
                )}
            </div>
        </div>
    )
}