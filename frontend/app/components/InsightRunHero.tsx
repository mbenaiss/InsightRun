'use client'

import Image from 'next/image'
import AppStoreLink from './AppStoreLink'
import { ThemedImage, useAutoplayInView, useSiteTheme } from './ThemedMedia'

export default function InsightRunHero() {
  const { mounted, reducedMotion, theme } = useSiteTheme()
  const observe = useAutoplayInView(!reducedMotion)

  return (
    <section id="hero" className="relative overflow-hidden pt-32 pb-24 lg:pt-40 lg:pb-32">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_50%_at_75%_35%,var(--glow),transparent_70%)]"
      />

      <div className="relative mx-auto grid max-w-6xl items-center gap-16 px-6 lg:grid-cols-[1.15fr_0.85fr] lg:gap-12">
        <div className="max-w-2xl">
          <h1 className="font-display text-[clamp(2.75rem,7vw,5.75rem)] font-extrabold leading-[0.98] tracking-[-0.045em]">
            <span className="block overflow-hidden pb-[0.08em]">
              <span className="rise text-muted-foreground" style={{ animationDelay: '0.1s' }}>
                Your watch records.
              </span>
            </span>
            <span className="block overflow-hidden pb-[0.08em]">
              <span className="rise text-foreground" style={{ animationDelay: '0.45s' }}>
                Insight Run explains.
              </span>
            </span>
          </h1>

          <p className="mt-8 max-w-xl text-lg leading-relaxed text-muted-foreground sm:text-xl">
            It reads your runs, sleep and heart rate from Apple Health and Strava, then tells you
            what they mean: how ready you are this morning, what each session did, and what to run
            next.
          </p>

          <div className="mt-10 flex flex-wrap items-center gap-x-8 gap-y-5">
            <AppStoreLink
              location="hero"
              className="rounded-[10px] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-primary"
            >
              <Image
                src="/app-store-badge.svg"
                alt="Download on the App Store"
                width={156}
                height={52}
                className="h-[52px] w-auto"
              />
            </AppStoreLink>
            <a
              href="#tour"
              className="text-base font-semibold text-foreground underline decoration-primary decoration-2 underline-offset-[6px] hover:text-primary"
            >
              Watch the 30-second tour
            </a>
          </div>

          <div className="mt-12 flex flex-wrap items-center gap-4">
            <span className="text-sm text-muted-foreground">Works with</span>
            <Image
              src="/apple-health-badge.svg"
              alt="Apple Health"
              width={150}
              height={44}
              className="h-11 w-auto"
            />
            <Image
              src="/strava-badge.svg"
              alt="Strava"
              width={150}
              height={44}
              className="h-11 w-auto"
            />
          </div>
        </div>

        <div className="relative mx-auto w-full max-w-[300px] sm:max-w-[320px]">
          <div className="rounded-[3.2rem] bg-gradient-to-b from-[#eceeea] to-[#a9ada7] p-[11px] shadow-[0_40px_100px_-30px_var(--glow),0_30px_60px_-30px_rgba(0,0,0,0.6)] ring-1 ring-line dark:from-[#2a2d2a] dark:to-[#0c0d0c]">
            <div className="relative aspect-[880/1912] overflow-hidden rounded-[2.6rem] bg-black">
              <ThemedImage
                name="insightrun-app-loop"
                dir="videos"
                alt="Insight Run showing a readiness score of 82 out of 100"
                width={600}
                height={1304}
                eager
                className="absolute inset-0 h-full w-full object-cover"
              />
              {mounted && !reducedMotion && (
                <video
                  key={theme}
                  ref={observe}
                  className="absolute inset-0 h-full w-full object-cover"
                  muted
                  loop
                  playsInline
                  preload="none"
                  aria-label="Insight Run screens: readiness, signals, runs, coach verdict, run analysis, plan and coach chat"
                >
                  <source src={`/videos/insightrun-app-loop-${theme}.mp4`} type="video/mp4" />
                </video>
              )}
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
