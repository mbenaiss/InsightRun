'use client'

import Image from 'next/image'

export default function InsightRunHero() {
  return (
    <section id="hero" className="relative pt-24 pb-20 lg:pt-32 lg:pb-32 overflow-hidden">
      {/* Background Gradients */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-full z-0 pointer-events-none">
        <div className="absolute top-[-10%] left-1/4 w-[500px] h-[500px] bg-primary/20 rounded-full blur-[100px] animate-pulse-glow" />
        <div className="absolute bottom-0 right-1/4 w-[400px] h-[400px] bg-secondary/20 rounded-full blur-[100px]" />
      </div>

      <div className="container mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="flex flex-col lg:flex-row items-center gap-16 lg:gap-24">
          {/* Text Content */}
          <div className="flex-1 text-center lg:text-left space-y-8 max-w-2xl mx-auto lg:mx-0">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-muted/50 border border-muted backdrop-blur-sm animate-fade-in">
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2 w-2 bg-blue-500"></span>
              </span>
              <span className="text-sm font-medium text-muted-foreground">
                New AI Analysis Engine
              </span>
            </div>

            <h1
              className="text-5xl sm:text-6xl lg:text-7xl font-bold tracking-tight leading-[1.1] animate-fade-in-up text-foreground"
              style={{ animationDelay: '0.1s' }}
            >
              Your AI Coach <br />
              <span className="text-gradient-primary">In Your Pocket</span>
            </h1>

            <p
              className="text-lg sm:text-xl text-muted-foreground leading-relaxed max-w-lg mx-auto lg:mx-0 animate-fade-in-up"
              style={{ animationDelay: '0.2s' }}
            >
              Advanced running analytics meets intelligent coaching. Track every metric, optimize
              recovery, and achieve your goals with insights from the world's most advanced AI.
            </p>

            <div
              className="flex flex-col sm:flex-row items-center justify-center lg:justify-start gap-4 pt-4 animate-fade-in-up"
              style={{ animationDelay: '0.3s' }}
            >
              <a
                href="https://apps.apple.com/us/app/insight-run/id6754607965"
                target="_blank"
                rel="noopener noreferrer"
                className="hover:scale-105 transition-transform duration-300"
              >
                <Image
                  src="/app-store-badge.svg"
                  alt="Download on the App Store"
                  width={156}
                  height={52}
                  className="h-[52px] w-auto"
                />
              </a>
            </div>
          </div>

          {/* Hero Image */}
          <div
            className="flex-1 relative w-full max-w-[320px] lg:max-w-md mx-auto perspective-1000 animate-fade-in-up"
            style={{ animationDelay: '0.4s' }}
          >
            <div className="relative z-10 animate-float">
              {/* Glow effect behind phone */}
              <div className="absolute -inset-4 bg-gradient-to-tr from-primary to-secondary rounded-[3rem] blur-2xl opacity-40" />

              <Image
                src="/screenshots/screenshot-01.png"
                alt="Insight Run app showing AI analysis"
                width={320}
                height={693}
                priority
                quality={95}
                className="relative w-full h-auto rounded-[2.5rem] border-[6px] border-gray-900 shadow-2xl"
              />

              {/* Floating Elements - optional cards */}
              <div
                className="absolute top-20 -left-12 bg-card/90 backdrop-blur-md p-4 rounded-2xl border border-muted shadow-xl hidden lg:block animate-float"
                style={{ animationDelay: '1s' }}
              >
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-green-500/20 flex items-center justify-center text-green-500">
                    <svg
                      aria-hidden="true"
                      className="w-6 h-6"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
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
                    <p className="text-xs text-muted-foreground">Recovery Score</p>
                    <p className="text-lg font-bold text-card-foreground">94%</p>
                  </div>
                </div>
              </div>

              <div
                className="absolute bottom-32 -right-12 bg-card/90 backdrop-blur-md p-4 rounded-2xl border border-muted shadow-xl hidden lg:block animate-float"
                style={{ animationDelay: '2s' }}
              >
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-blue-500/20 flex items-center justify-center text-blue-500">
                    <svg
                      aria-hidden="true"
                      className="w-6 h-6"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                      />
                    </svg>
                  </div>
                  <div>
                    <p className="text-xs text-muted-foreground">Weekly Distance</p>
                    <p className="text-lg font-bold text-card-foreground">42.5 km</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
