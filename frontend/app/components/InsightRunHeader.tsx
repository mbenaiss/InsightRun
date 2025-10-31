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
              <Link
                href="/privacy"
                className="text-gray-300 hover:text-blue-400 font-medium transition-colors"
              >
                Privacy
              </Link>
            </nav>

            {/* CTA Button */}
            <div className="flex items-center gap-4">
              <button
                type="button"
                disabled
                className="px-6 py-2 bg-slate-700 text-gray-400 rounded-lg font-medium text-sm cursor-not-allowed"
              >
                Coming Soon
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Spacer for fixed header */}
      <div className="h-16" />
    </>
  )
}
