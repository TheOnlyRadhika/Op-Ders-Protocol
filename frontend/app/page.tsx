'use client'

import Header from '@/components/header'
import CreditCard from '@/components/creditcard'
import PoolStats from '@/components/poolstats'
import Actions from '@/components/actions'
import WriteOptionsForm from '@/components/writeOptionsForm'
import BorrowForm from '@/components/borrowForm'
import OptionsMarketplace from '@/components/OptionsMarketplace'
import TransactionHistory from '@/components/transactionHistory'
import { useState } from 'react'

export default function Home() {
  const [activeSection, setActiveSection] = useState('overview')

  return (
    <main className="min-h-screen bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900">
      <Header />

      <div className="max-w-7xl mx-auto px-4 py-12">
        {/* Hero Section */}
        <div className="mb-12">
          <h1 className="text-5xl font-bold text-white mb-4">
            DeFi Options + Credit-Backed Lending
          </h1>
          <p className="text-xl text-white/60 max-w-2xl">
            Trade options with 75% less collateral. Earn up to 5% APR on deposits.
            All powered by on-chain credit scoring.
          </p>
        </div>

        {/* Navigation Tabs */}
        <div className="flex gap-2 mb-8 overflow-x-auto pb-2">
          {[
            { id: 'overview', label: '📊 Overview' },
            { id: 'deposit', label: '💰 Deposit' },
            { id: 'write', label: '📝 Write Options' },
            { id: 'borrow', label: '📈 Borrow' },
            { id: 'marketplace', label: '🛍️ Marketplace' },
            { id: 'history', label: '📜 History' },
          ].map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveSection(tab.id)}
              className={`px-4 py-2 rounded-lg font-bold whitespace-nowrap transition ${activeSection === tab.id
                ? 'bg-purple-500/30 border border-purple-500 text-purple-300'
                : 'bg-white/10 border border-white/20 text-white hover:bg-white/20'
                }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Overview Section */}
        {activeSection === 'overview' && (
          <>
            <div className="mb-12">
              <h2 className="text-2xl font-bold text-white mb-6">Your Profile</h2>
              <CreditCard />
            </div>

            <div className="mb-12">
              <h2 className="text-2xl font-bold text-white mb-6">Protocol Stats</h2>
              <PoolStats />
            </div>
          </>
        )}

        {/* Deposit Section */}
        {activeSection === 'deposit' && (
          <div className="mb-12">
            <h2 className="text-2xl font-bold text-white mb-6">Deposit & Earn</h2>
            <Actions />
          </div>
        )}

        {/* Write Options Section */}
        {activeSection === 'write' && (
          <div className="mb-12">
            <h2 className="text-2xl font-bold text-white mb-6">Create Options</h2>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <WriteOptionsForm />
              <div className="bg-gradient-to-br from-blue-500/20 to-blue-600/20 rounded-lg p-6 border border-blue-500/30">
                <h3 className="text-lg font-bold text-white mb-4">ℹ️ How It Works</h3>
                <ul className="space-y-3 text-white/80 text-sm">
                  <li>✅ Write covered calls to earn premiums</li>
                  <li>✅ Write puts for downside protection</li>
                  <li>✅ Use credit-backing to reduce collateral</li>
                  <li>✅ Higher credit score = less collateral needed</li>
                  <li>✅ Successful options boost your credit score</li>
                  <li>✅ Earn passive income on options premiums</li>
                </ul>
              </div>
            </div>
          </div>
        )}

        {/* Borrow Section */}
        {activeSection === 'borrow' && (
          <div className="mb-12">
            <h2 className="text-2xl font-bold text-white mb-6">Under-Collateralized Lending</h2>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <BorrowForm />
              <div className="bg-gradient-to-br from-green-500/20 to-green-600/20 rounded-lg p-6 border border-green-500/30">
                <h3 className="text-lg font-bold text-white mb-4">💡 Loan Details</h3>
                <ul className="space-y-3 text-white/80 text-sm">
                  <li>📊 Score 300-600: 100% collateral required (8% APR)</li>
                  <li>📈 Score 600-800: 50% collateral required (5% APR)</li>
                  <li>🌟 Score 800+: 25% collateral required (2% APR)</li>
                  <li>⚡ Borrow up to 4x your collateral</li>
                  <li>✅ No hidden fees or surprises</li>
                  <li>📅 Flexible repayment terms</li>
                </ul>
              </div>
            </div>
          </div>
        )}

        {/* Marketplace Section */}
        {activeSection === 'marketplace' && (
          <div className="mb-12">
            <h2 className="text-2xl font-bold text-white mb-6">My Options & Actions</h2>
            <OptionsMarketplace />
          </div>
        )}

        {/* History Section */}
        {activeSection === 'history' && (
          <div className="mb-12">
            <h2 className="text-2xl font-bold text-white mb-6">Transaction History</h2>
            <TransactionHistory />
          </div>
        )}

        {/* Footer */}
        <div className="border-t border-white/10 pt-8 mt-16">
          <p className="text-white/40 text-center">
            OptionsCredit Protocol v1.0 | Sepolia Testnet Only
          </p>
          <p className="text-white/40 text-center text-sm mt-2">
            Always verify contract addresses on Etherscan before interacting
          </p>
          <p className="text-white/40 text-center text-xs mt-4">
            🔒 Your funds are secured by smart contracts. Never share your private key.
          </p>
        </div>
      </div>
    </main>
  )
}