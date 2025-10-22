import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  /* config options here */
  output: 'standalone',
  // Enable SSR for all pages by default
  experimental: {
    // Required for Cloudflare Workers compatibility
  },
  images: {
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
