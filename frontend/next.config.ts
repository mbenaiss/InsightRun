import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  /* config options here */
  output: 'standalone',
  // Analytics go through our own domain: browser blocklists drop requests to the provider's
  // hosts, which left the landing page's traffic largely unmeasured.
  async rewrites() {
    return [
      {
        source: '/ingest/static/:path*',
        destination: 'https://eu-assets.i.posthog.com/static/:path*',
      },
      { source: '/ingest/:path*', destination: 'https://eu.i.posthog.com/:path*' },
    ]
  },
  skipTrailingSlashRedirect: true,
  // Enable SSR for all pages by default
  experimental: {
    // Required for Cloudflare Workers compatibility
  },
  images: {
    qualities: [75, 85, 90, 95, 100],
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'img.youtube.com',
        pathname: '/vi/**',
      },
      {
        protocol: 'https',
        hostname: 'cdn.derentalequipment.com',
        pathname: '/equipment_library/**',
      },
    ],
  },
}

export default nextConfig
