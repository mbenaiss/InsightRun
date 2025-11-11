import Image from 'next/image'
import Link from 'next/link'

export default function InsightRunFooter() {
  return (
    <footer className="bg-slate-950 text-white py-12">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-8">
          {/* Brand Column */}
          <div className="col-span-1 md:col-span-2">
            <div className="flex items-center gap-3 mb-4">
              <Image
                src="/app-icon.png"
                alt="InsightRun logo"
                width={40}
                height={40}
                className="w-10 h-10 rounded-xl"
              />
              <span className="text-xl font-bold">Insight Run</span>
            </div>
            <p className="text-gray-400 mb-4 max-w-sm">
              Your AI-powered running coach. Track workouts, optimize recovery, and get personalized
              insights with HealthKit integration.
            </p>
            <a
              href="https://apps.apple.com/us/app/insight-run/id6754607965"
              target="_blank"
              rel="noopener noreferrer"
              className="text-sm text-blue-400 hover:text-blue-300 transition-colors inline-flex items-center gap-2"
            >
              Download on the App Store
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
              </svg>
            </a>
          </div>

          {/* Product Column */}
          <div>
            <h3 className="font-semibold mb-4">Product</h3>
            <ul className="space-y-2">
              <li>
                <a href="#features" className="text-gray-400 hover:text-blue-400 transition-colors">
                  Features
                </a>
              </li>
              <li>
                <a
                  href="https://apps.apple.com/us/app/insight-run/id6754607965"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-gray-400 hover:text-blue-400 transition-colors"
                >
                  Download
                </a>
              </li>
            </ul>
          </div>

          {/* Legal Column */}
          <div>
            <h3 className="font-semibold mb-4">Legal</h3>
            <ul className="space-y-2">
              <li>
                <Link
                  href="/privacy"
                  className="text-gray-400 hover:text-blue-400 transition-colors"
                >
                  Privacy Policy
                </Link>
              </li>
              <li>
                <Link href="/terms" className="text-gray-400 hover:text-blue-400 transition-colors">
                  Terms of Service
                </Link>
              </li>
              <li>
                <Link
                  href="/support"
                  className="text-gray-400 hover:text-blue-400 transition-colors"
                >
                  Support
                </Link>
              </li>
              <li>
                <a
                  href="mailto:support@altcode.studio"
                  className="text-gray-400 hover:text-blue-400 transition-colors"
                >
                  Contact
                </a>
              </li>
            </ul>
          </div>
        </div>

        {/* Bottom Bar */}
        <div className="mt-12 pt-8 border-t border-slate-800">
          <div className="flex justify-center">
            <p className="text-gray-400 text-sm">© 2025 Insight Run. All rights reserved.</p>
          </div>
        </div>
      </div>
    </footer>
  )
}
