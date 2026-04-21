
import { sepolia } from 'wagmi/chains'
import { http, createConfig } from 'wagmi'
import { injected, coinbaseWallet, walletConnect } from 'wagmi/connectors'

export const wagmiConfig = createConfig({
    chains: [sepolia],
    connectors: [
        injected(),
        coinbaseWallet(),
        walletConnect({ projectId: 'YOUR_WALLETCONNECT_PROJECT_ID' }),
    ],
    transports: {
        [sepolia.id]: http('process.env.NEXT_PUBLIC_RPC_URL'),
    },
})