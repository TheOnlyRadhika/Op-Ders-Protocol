import type { Metadata } from 'next'
import { Providers } from './providers'
import './globals.css'

export const metadata: Metadata = {
  title: 'OptionsCredit - DeFi Protocol',
  description: 'Options Trading + Under-Collateralized Lending',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className="bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900">
        <Providers>{children}</Providers>
      </body>
    </html>
  )
}