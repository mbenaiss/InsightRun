'use client'

export default function InsightRunHero() {
  return (
    // biome-ignore lint/correctness/useUniqueElementIds: Static section ID for navigation
    <section
      id="hero"
      className="pt-24 md:pt-32 pb-20 md:pb-32 relative overflow-hidden bg-gradient-to-b from-blue-50 to-white"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
          {/* Left Column - Content */}
          <div className="space-y-8">
            <div className="flex items-center gap-2">
              <div className="bg-blue-600 text-white px-4 py-1.5 rounded-full text-sm font-medium">
                Coming Soon to App Store
              </div>
            </div>

            <h1 className="text-5xl md:text-6xl lg:text-7xl font-bold leading-tight">
              Your AI-Powered
              <span className="bg-gradient-to-r from-blue-600 to-cyan-600 bg-clip-text text-transparent">
                {' '}
                Running Coach
              </span>
            </h1>

            <p className="text-xl md:text-2xl text-gray-600 leading-relaxed">
              Track your workouts with advanced metrics, optimize your recovery, and get
              personalized AI coaching insights powered by HealthKit.
            </p>

            <div className="flex flex-col sm:flex-row gap-4 pt-4">
              <button
                type="button"
                disabled
                className="px-8 py-4 bg-gray-300 text-gray-600 rounded-xl font-bold text-lg inline-flex items-center justify-center gap-2 cursor-not-allowed"
              >
                <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 22 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.09997 22C7.78997 22.05 6.79997 20.68 5.95997 19.47C4.24997 17 2.93997 12.45 4.69997 9.39C5.56997 7.87 7.12997 6.91 8.81997 6.88C10.1 6.86 11.32 7.75 12.11 7.75C12.89 7.75 14.37 6.68 15.92 6.84C16.57 6.87 18.39 7.1 19.56 8.82C19.47 8.88 17.39 10.1 17.41 12.63C17.44 15.65 20.06 16.66 20.09 16.67C20.06 16.74 19.67 18.11 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.6 4.35 14.9 5.19C14.21 6.04 13.07 6.7 11.95 6.61C11.8 5.46 12.36 4.26 13 3.5Z" />
                </svg>
                Available Soon
              </button>

              <a
                href="/privacy"
                className="px-8 py-4 border-2 border-gray-300 text-gray-700 rounded-xl font-bold text-lg inline-flex items-center justify-center gap-2 hover:border-blue-600 hover:text-blue-600 transition-all"
              >
                Privacy Policy
              </a>
            </div>

            {/* Features List */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-8">
              <div className="flex items-start gap-3">
                <div className="flex-shrink-0 w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
                  <svg
                    className="w-5 h-5 text-blue-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M13 10V3L4 14h7v7l9-11h-7z"
                    />
                  </svg>
                </div>
                <div>
                  <h3 className="font-semibold text-gray-900">Advanced Metrics</h3>
                  <p className="text-sm text-gray-600">Pace, cadence, power, splits & more</p>
                </div>
              </div>

              <div className="flex items-start gap-3">
                <div className="flex-shrink-0 w-8 h-8 bg-cyan-100 rounded-lg flex items-center justify-center">
                  <svg
                    className="w-5 h-5 text-cyan-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
                    />
                  </svg>
                </div>
                <div>
                  <h3 className="font-semibold text-gray-900">AI Coaching</h3>
                  <p className="text-sm text-gray-600">Personalized insights & recommendations</p>
                </div>
              </div>

              <div className="flex items-start gap-3">
                <div className="flex-shrink-0 w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center">
                  <svg
                    className="w-5 h-5 text-green-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                    />
                  </svg>
                </div>
                <div>
                  <h3 className="font-semibold text-gray-900">Recovery Score</h3>
                  <p className="text-sm text-gray-600">Daily readiness based on HRV & sleep</p>
                </div>
              </div>

              <div className="flex items-start gap-3">
                <div className="flex-shrink-0 w-8 h-8 bg-purple-100 rounded-lg flex items-center justify-center">
                  <svg
                    className="w-5 h-5 text-purple-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
                    />
                  </svg>
                </div>
                <div>
                  <h3 className="font-semibold text-gray-900">Privacy First</h3>
                  <p className="text-sm text-gray-600">Your data stays on your device</p>
                </div>
              </div>
            </div>
          </div>

          {/* Right Column - App Preview */}
          <div className="relative lg:pl-8">
            <div className="relative">
              {/* Gradient Background Blur */}
              <div className="absolute -inset-4 bg-gradient-to-r from-blue-400 to-cyan-400 rounded-3xl blur-3xl opacity-20" />

              {/* Phone Mockup Placeholder */}
              <div className="relative bg-gray-900 rounded-[3rem] p-3 shadow-2xl max-w-sm mx-auto">
                <div className="bg-white rounded-[2.5rem] overflow-hidden aspect-[9/19]">
                  {/* Placeholder for app screenshot */}
                  <div className="bg-gradient-to-br from-blue-50 to-cyan-50 h-full flex items-center justify-center">
                    <div className="text-center p-8">
                      <div className="w-24 h-24 bg-gradient-to-br from-blue-600 to-cyan-600 rounded-3xl mx-auto mb-6 flex items-center justify-center shadow-lg">
                        <svg
                          className="w-12 h-12 text-white"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            strokeWidth={2}
                            d="M13 10V3L4 14h7v7l9-11h-7z"
                          />
                        </svg>
                      </div>
                      <h3 className="text-2xl font-bold text-gray-900 mb-2">InsightRun</h3>
                      <p className="text-gray-600">Coming Soon</p>
                      <div className="mt-8 space-y-4">
                        <div className="h-2 bg-gray-200 rounded animate-pulse" />
                        <div className="h-2 bg-gray-200 rounded animate-pulse w-3/4 mx-auto" />
                        <div className="h-2 bg-gray-200 rounded animate-pulse w-1/2 mx-auto" />
                      </div>
                    </div>
                  </div>
                </div>

                {/* Notch */}
                <div className="absolute top-6 left-1/2 transform -translate-x-1/2 w-32 h-7 bg-gray-900 rounded-full" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
