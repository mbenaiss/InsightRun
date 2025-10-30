'use client'

export default function InsightRunHero() {
  return (
    <section
      id="hero"
      className="pt-24 md:pt-32 pb-20 md:pb-32 relative overflow-hidden bg-[#fefbf7]"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        {/* Hero Content - Centered */}
        <div className="max-w-5xl mx-auto text-center space-y-8 mb-16">
          <div className="inline-flex items-center gap-2">
            <div className="bg-[#0094FF] text-white px-4 py-1.5 rounded-full text-sm font-semibold">
              Coming Soon to App Store
            </div>
          </div>

          <h1 className="text-5xl md:text-6xl lg:text-7xl font-bold leading-tight text-[#1a2942]">
            Run smarter with AI-powered insights
          </h1>

          <p className="text-xl md:text-2xl text-gray-600 leading-relaxed max-w-3xl mx-auto">
            Advanced running analytics meets intelligent coaching. Track every metric, optimize
            recovery, and achieve your goals with insights from the world's most advanced AI.
          </p>

          <div className="flex flex-col sm:flex-row gap-4 pt-4 justify-center">
            <button
              type="button"
              disabled
              className="px-8 py-4 bg-gray-300 text-gray-600 rounded-2xl font-semibold text-lg inline-flex items-center justify-center gap-2 cursor-not-allowed"
            >
              <svg
                className="w-6 h-6"
                fill="currentColor"
                viewBox="0 0 24 24"
                role="img"
                aria-label="Apple logo"
              >
                <path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 22 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.09997 22C7.78997 22.05 6.79997 20.68 5.95997 19.47C4.24997 17 2.93997 12.45 4.69997 9.39C5.56997 7.87 7.12997 6.91 8.81997 6.88C10.1 6.86 11.32 7.75 12.11 7.75C12.89 7.75 14.37 6.68 15.92 6.84C16.57 6.87 18.39 7.1 19.56 8.82C19.47 8.88 17.39 10.1 17.41 12.63C17.44 15.65 20.06 16.66 20.09 16.67C20.06 16.74 19.67 18.11 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.6 4.35 14.9 5.19C14.21 6.04 13.07 6.7 11.95 6.61C11.8 5.46 12.36 4.26 13 3.5Z" />
              </svg>
              Available Soon
            </button>

            <a
              href="/privacy"
              className="px-8 py-4 border-2 border-[#1a2942] text-[#1a2942] rounded-2xl font-semibold text-lg inline-flex items-center justify-center gap-2 hover:bg-[#1a2942] hover:text-white transition-all"
            >
              Privacy Policy
            </a>
          </div>
        </div>
      </div>
    </section>
  )
}
