'use client'

import Image from 'next/image'

export default function InsightRunHero() {
  return (
    <section
      id="hero"
      className="pt-24 md:pt-32 pb-20 md:pb-32 relative overflow-hidden bg-[#0f172a]"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 relative">
        <div className="grid lg:grid-cols-2 gap-12 lg:gap-16 items-center">
          {/* Left Column - Text Content */}
          <div className="space-y-8 text-center lg:text-left">
            <div className="inline-flex items-center gap-2">
              <div className="bg-gradient-to-r from-[#0094FF] to-[#64B0FF] text-white px-4 py-1.5 rounded-full text-sm font-semibold">
                Available on App Store
              </div>
            </div>

            <h1 className="text-5xl md:text-6xl lg:text-7xl font-bold leading-tight text-white">
              AI Coach in Your Pocket
            </h1>

            <p className="text-xl md:text-2xl text-gray-300 leading-relaxed">
              Advanced running analytics meets intelligent coaching. Track every metric, optimize
              recovery, and achieve your goals with insights from the world's most advanced AI.
            </p>

            <div className="flex justify-center lg:justify-start pt-4">
              <a
                href="https://apps.apple.com/us/app/insight-run/id6754607965"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-block hover:opacity-80 transition-opacity"
              >
                <Image
                  src="/app-store-badge.svg"
                  alt="Download on the App Store"
                  width={160}
                  height={53}
                  className="h-[53px] w-auto"
                />
              </a>
            </div>
          </div>

          {/* Right Column - App Screenshot Preview */}
          <div className="relative flex justify-center lg:justify-end">
            <div className="max-w-[320px] w-full">
              <Image
                src="/screenshots/screenshot-01.png"
                alt="Insight Run app showing AI analysis of workout details"
                width={320}
                height={693}
                priority
                quality={85}
                className="w-full h-auto drop-shadow-[0_20px_50px_rgba(0,0,0,0.6)] rounded-[2.5rem]"
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
