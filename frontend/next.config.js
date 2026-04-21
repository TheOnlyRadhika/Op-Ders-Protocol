// @ts-nocheck

/** @type {import('next').NextConfig} */
const nextConfig = {
  // 1. In Next.js 16+, turbo is a top-level key!
  turbo: {
    resolveAlias: {
      'pino-pretty': 'pino-pretty',
      'lokijs': 'lokijs',
      'encoding': 'encoding',
    },
  },

  // 2. Keep this for compatibility with Web3 libraries
  webpack: (config) => {
    config.externals.push('pino-pretty', 'lokijs', 'encoding');
    config.resolve.fallback = { fs: false, net: false, tls: false };
    return config;
  },
};

module.exports = nextConfig;