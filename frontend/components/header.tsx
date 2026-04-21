'use client'

import { ConnectButton } from '@rainbow-me/rainbowkit'

export default function Header() {
    return (
        <header className="sticky top-0 z-50 bg-black/50 backdrop-blur-md border-b border-white/10">
            <div className="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
                {/* Logo */}
                <div className="flex items-center gap-2">
                    <div className="text-2xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-purple-400 to-pink-400">
                        OptionsCredit
                    </div>
                </div>

                {/* Network Badge */}
                <div className="hidden sm:flex items-center gap-2 px-3 py-1 bg-purple-500/20 rounded-full border border-purple-500/50">
                    <span className="w-2 h-2 rounded-full bg-green-400"></span>
                    <span className="text-sm text-white">Sepolia Testnet</span>
                </div>

                {/* Connect Wallet Button */}
                <ConnectButton />
            </div>
        </header>
    )
}
