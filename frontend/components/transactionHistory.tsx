'use client'

import { useAccount } from 'wagmi'
import { useQuery } from "wagmi/query"
import { useQuery as useReactQuery } from '@tanstack/react-query'
import api from '@/lib/api'
import { useState, useEffect } from 'react'

export default function TransactionHistory() {
    const { address } = useAccount()
    const [transactions, setTransactions] = useState<any[]>([])

    // Fetch transactions
    useEffect(() => {
        if (!address) return

        const fetchTransactions = async () => {
            try {
                const data = await api.get(`/transactions/${address}`)
                setTransactions(data.data.transactions || [])
            } catch (error) {
                console.error('Error fetching transactions:', error)
            }
        }

        fetchTransactions()

        // Poll every 5 seconds for new transactions
        const interval = setInterval(fetchTransactions, 5000)

        return () => clearInterval(interval)
    }, [address])

    if (!address) {
        return (
            <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
                <p className="text-white/60">Connect wallet to see transaction history</p>
            </div>
        )
    }

    if (transactions.length === 0) {
        return (
            <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
                <p className="text-white/60">No transactions yet</p>
            </div>
        )
    }

    const getTransactionColor = (type: string) => {
        switch (type) {
            case 'OptionCreated':
            case 'Deposit':
                return 'text-green-400'
            case 'OptionBought':
            case 'LoanCreated':
                return 'text-blue-400'
            case 'OptionExercised':
            case 'LoanRepaid':
                return 'text-purple-400'
            case 'OptionExpired':
            case 'LoanDefaulted':
                return 'text-red-400'
            default:
                return 'text-white'
        }
    }

    const getTransactionIcon = (type: string) => {
        switch (type) {
            case 'OptionCreated':
                return '📝'
            case 'OptionBought':
                return '🛍️'
            case 'OptionExercised':
                return '⚡'
            case 'OptionExpired':
                return '⏰'
            case 'Deposit':
                return '💰'
            case 'LoanCreated':
                return '📊'
            case 'LoanRepaid':
                return '✅'
            case 'LoanDefaulted':
                return '⚠️'
            default:
                return '📌'
        }
    }

    return (
        <div className="bg-gradient-to-br from-slate-800/50 to-slate-700/50 rounded-lg p-6 border border-white/10">
            <h3 className="text-lg font-bold text-white mb-4">Transaction History</h3>

            <div className="space-y-3 max-h-96 overflow-y-auto">
                {transactions.map((tx, idx) => (
                    <div
                        key={idx}
                        className="bg-white/5 hover:bg-white/10 rounded-lg p-4 border border-white/10 transition flex justify-between items-start"
                    >
                        <div className="flex gap-3 flex-1">
                            <span className="text-2xl">{getTransactionIcon(tx.type)}</span>
                            <div>
                                <p className={`font-bold ${getTransactionColor(tx.type)}`}>
                                    {tx.type.replace(/([A-Z])/g, ' $1').trim()}
                                </p>
                                <p className="text-white/60 text-sm">
                                    {new Date(tx.timestamp).toLocaleDateString()} at{' '}
                                    {new Date(tx.timestamp).toLocaleTimeString()}
                                </p>

                                {/* Show relevant details */}
                                {tx.amount && (
                                    <p className="text-white/80 text-sm mt-1">
                                        Amount: ${parseFloat(tx.amount).toFixed(2)}
                                    </p>
                                )}
                                {tx.premium && (
                                    <p className="text-white/80 text-sm">
                                        Premium: ${parseFloat(tx.premium).toFixed(2)}
                                    </p>
                                )}
                                {tx.strikePrice && (
                                    <p className="text-white/80 text-sm">
                                        Strike: ${parseFloat(tx.strikePrice).toFixed(2)}
                                    </p>
                                )}
                                {tx.totalRepaid && (
                                    <p className="text-white/80 text-sm">
                                        Repaid: ${parseFloat(tx.totalRepaid).toFixed(2)}
                                    </p>
                                )}
                            </div>
                        </div>

                        {/* TX Hash Link */}
                        {tx.txHash && (
                            <a
                                href={`https://sepolia.etherscan.io/tx/${tx.txHash}`}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="text-purple-400 hover:text-purple-300 text-sm underline ml-4"
                            >
                                View
                            </a>
                        )}
                    </div>
                ))}
            </div>
        </div>
    )
}