import posthog from 'posthog-js'

type LandingEvents = {
  app_store_clicked: { location: 'header' | 'hero' | 'cta' | 'footer' }
  tour_started: { theme: string }
  tour_progress: { percent: 25 | 50 | 75 | 100 }
  tour_chapter_clicked: { chapter: string; at: number }
  tour_sound_toggled: { sound: 'on' | 'off' }
}

export function track<K extends keyof LandingEvents>(
  name: K,
  ...props: LandingEvents[K] extends undefined ? [] : [LandingEvents[K]]
) {
  if (!posthog.__loaded) return
  posthog.capture(name, props[0])
}
