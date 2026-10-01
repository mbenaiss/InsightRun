'use client'

import { useCallback, useRef, useState } from 'react'
import { track } from '../lib/analytics'
import { ThemedImage, useAutoplayInView, useSiteTheme } from './ThemedMedia'

const chapters = [
  { at: 2, label: 'Readiness' },
  { at: 5, label: 'Signals' },
  { at: 8, label: 'Your runs' },
  { at: 10, label: 'Coach verdict' },
  { at: 13.5, label: 'Run analysis' },
  { at: 16.5, label: 'Training plan' },
  { at: 21.5, label: 'Ask your coach' },
]

const timestamp = (s: number) => `0:${String(Math.floor(s)).padStart(2, '0')}`

export default function InsightRunTour() {
  const { mounted, reducedMotion, theme } = useSiteTheme()
  const observe = useAutoplayInView(!reducedMotion)
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const [muted, setMuted] = useState(true)
  const started = useRef(false)
  const watched = useRef(0)
  const reported = useRef(new Set<number>())

  const setVideo = useCallback(
    (video: HTMLVideoElement | null) => {
      videoRef.current = video
      const stopObserving = observe(video)
      if (!video) return stopObserving

      // Progress counts seconds actually played, so a chapter jump doesn't read as watched.
      let last = video.currentTime
      const onPlay = () => {
        if (started.current) return
        started.current = true
        track('tour_started', { theme })
      }
      const onTimeUpdate = () => {
        const delta = video.currentTime - last
        last = video.currentTime
        if (delta > 0 && delta < 1) watched.current += delta
        if (!video.duration) return
        const ratio = watched.current / video.duration
        for (const percent of [25, 50, 75, 100] as const) {
          if (ratio >= percent / 100 - 0.03 && !reported.current.has(percent)) {
            reported.current.add(percent)
            track('tour_progress', { percent })
          }
        }
      }
      video.addEventListener('play', onPlay)
      video.addEventListener('timeupdate', onTimeUpdate)
      return () => {
        video.removeEventListener('play', onPlay)
        video.removeEventListener('timeupdate', onTimeUpdate)
        stopObserving?.()
      }
    },
    [observe, theme]
  )

  const seek = (chapter: string, at: number) => {
    const video = videoRef.current
    if (!video) return
    track('tour_chapter_clicked', { chapter, at })
    video.currentTime = at
    video.play().catch(() => {})
  }

  const toggleSound = () => {
    const video = videoRef.current
    if (!video) return
    video.muted = !video.muted
    setMuted(video.muted)
    track('tour_sound_toggled', { sound: video.muted ? 'off' : 'on' })
    if (!video.muted) video.play().catch(() => {})
  }

  return (
    <section id="tour" className="border-t border-line py-24 lg:py-32">
      <div className="mx-auto grid max-w-6xl items-center gap-16 px-6 lg:grid-cols-[1fr_auto] lg:gap-24">
        <div className="max-w-xl">
          <h2 className="font-display text-4xl font-extrabold tracking-[-0.035em] sm:text-5xl">
            The 30-second tour
          </h2>
          <p className="mt-5 text-lg text-muted-foreground">
            Real screens from the app, in the order you would use them. Pick a moment to jump to it.
          </p>
          <ul className="mt-10 grid gap-1 sm:grid-cols-2 sm:gap-x-8">
            {chapters.map((c) => (
              <li key={c.label}>
                <button
                  type="button"
                  onClick={() => seek(c.label, c.at)}
                  disabled={!mounted}
                  className="flex w-full items-baseline gap-4 rounded-lg px-3 py-2.5 text-left hover:bg-muted focus-visible:outline-2 focus-visible:outline-primary"
                >
                  <span className="font-rounded text-sm tabular-nums text-primary">
                    {timestamp(c.at)}
                  </span>
                  <span className="text-foreground">{c.label}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>

        <div className="relative mx-auto w-full max-w-[340px] lg:w-[360px]">
          <div className="relative aspect-[886/1920] overflow-hidden rounded-[28px] ring-1 ring-line shadow-[0_40px_100px_-30px_var(--glow)]">
            <ThemedImage
              name="insightrun-preview"
              dir="videos"
              alt="Insight Run app preview"
              width={720}
              height={1560}
              className="absolute inset-0 h-full w-full object-cover"
            />
            {mounted && (
              <video
                key={theme}
                ref={setVideo}
                className="absolute inset-0 h-full w-full object-cover"
                muted
                loop
                playsInline
                preload="none"
                controls={reducedMotion}
                aria-label="Insight Run app preview: readiness, signals, runs, coach verdict, run analysis, training plan and AI coach"
              >
                <source src={`/videos/insightrun-preview-${theme}.mp4`} type="video/mp4" />
              </video>
            )}
          </div>
          {mounted && !reducedMotion && (
            <button
              type="button"
              onClick={toggleSound}
              className="mt-4 rounded-full px-4 py-2 text-sm font-semibold text-foreground ring-1 ring-line hover:bg-muted focus-visible:outline-2 focus-visible:outline-primary"
              aria-pressed={!muted}
            >
              {muted ? 'Turn sound on' : 'Turn sound off'}
            </button>
          )}
        </div>
      </div>
    </section>
  )
}
