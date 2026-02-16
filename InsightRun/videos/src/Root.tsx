import { Composition } from 'remotion'
import { AppPreview } from './AppPreview'

// App Store Preview: 30fps, max 30 seconds = 900 frames
// iPhone 17 Pro Max: 1320x2868
const FPS = 30
const DURATION_SECONDS = 30
const WIDTH = 1320
const HEIGHT = 2868

export type CalloutConfig = {
  text: string
  startFrame: number
  durationFrames: number
  position: 'top' | 'bottom'
}

export type AppPreviewProps = {
  videoFile: string
  playbackRate: number
  trimStartSeconds: number
  callouts: CalloutConfig[]
}

// en-US: raw 67s, trim 10s → 57s usable, 2.0x → 28.5s + 2s intro
// Old test flow (source time after trim, accounting for ~20s overhead):
//   Dashboard ~20s, Workouts ~23s, Detail ~25s, AI scroll ~28s,
//   Statistics ~32s, Progression ~34s, Recovery ~39s, Readiness ~42s, AI Coach ~48s
// Output time = 2 + (source - 0) / 2.0
const enCallouts: CalloutConfig[] = [
  { text: 'Recovery Dashboard', startFrame: 12 * FPS, durationFrames: 3.5 * FPS, position: 'bottom' },
  { text: 'Workout Details', startFrame: 16 * FPS, durationFrames: 3.5 * FPS, position: 'bottom' },
  { text: 'AI Analysis', startFrame: 20 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
  { text: 'Training Stats', startFrame: 23.5 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
  { text: 'Readiness Score', startFrame: 27 * FPS, durationFrames: 2.5 * FPS, position: 'bottom' },
]

// fr-FR: raw 86s, trim 10s → 76s usable, 2.7x → 28.1s + 2s intro
// Overhead is larger (~35s), content starts later in output
const frCallouts: CalloutConfig[] = [
  { text: 'Tableau de Récupération', startFrame: 15 * FPS, durationFrames: 3.5 * FPS, position: 'bottom' },
  { text: "Détail d'Entraînement", startFrame: 19 * FPS, durationFrames: 3.5 * FPS, position: 'bottom' },
  { text: 'Analyse IA', startFrame: 23 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
  { text: 'Statistiques', startFrame: 26.5 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
]

export const RemotionRoot = () => {
  return (
    <>
      <Composition
        id="AppPreview-en"
        component={AppPreview}
        durationInFrames={FPS * DURATION_SECONDS}
        fps={FPS}
        width={WIDTH}
        height={HEIGHT}
        defaultProps={{
          videoFile: 'en-US_raw.mov',
          playbackRate: 2.0,
          trimStartSeconds: 10,
          callouts: enCallouts,
        }}
      />
      <Composition
        id="AppPreview-fr"
        component={AppPreview}
        durationInFrames={FPS * DURATION_SECONDS}
        fps={FPS}
        width={WIDTH}
        height={HEIGHT}
        defaultProps={{
          videoFile: 'fr-FR_raw.mov',
          playbackRate: 2.7,
          trimStartSeconds: 10,
          callouts: frCallouts,
        }}
      />
    </>
  )
}
