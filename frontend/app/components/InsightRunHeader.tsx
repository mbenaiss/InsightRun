'use client'

import Image from 'next/image'
import Link from 'next/link'

export default function InsightRunHeader() {
  return (
    <>
      {/* Header */}
      <header className="fixed top-0 w-full bg-slate-900/80 backdrop-blur-lg z-50 border-b border-slate-800">
        <div className="container mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            {/* Logo */}
            <Link href="/" className="flex items-center gap-3">
              <Image
                src="/app-icon.png"
                alt="InsightRun logo"
                width={40}
                height={40}
                className="w-10 h-10 rounded-xl"
              />
              <span className="text-xl font-bold text-white">Insight Run</span>
            </Link>

            {/* Navigation */}
            <nav className="hidden md:flex items-center gap-8">
              <a
                href="#features"
                className="text-gray-300 hover:text-blue-400 font-medium transition-colors"
              >
                Features
              </a>
            </nav>

            {/* CTA Button */}
            <div className="flex items-center gap-4">
              <a
                href="https://apps.apple.com/us/app/insight-run/id6754607965"
                target="_blank"
                rel="noopener noreferrer"
                className="px-6 py-2 bg-gradient-to-r from-[#0094FF] to-[#64B0FF] text-white rounded-lg font-medium text-sm hover:opacity-90 transition-all"
              >
                Download
              </a>
            </div>
          </div>
        </div>
      </header>

      {/* Spacer for fixed header */}
      <div className="h-16" />
    </>
  )
}
