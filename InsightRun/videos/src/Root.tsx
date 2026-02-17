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
  description?: string
  startFrame: number
  durationFrames: number
  position: 'top' | 'bottom'
}

export type AppPreviewProps = {
  videoFile: string
  playbackRate: number
  trimStartSeconds: number
  callouts: CalloutConfig[]
  subtitle: string
  endCardCta: string
}

// en-US: raw 67s, trim 10s → 57s usable, 2.0x → 28.5s + 2s intro
// Old test flow (source time after trim, accounting for ~20s overhead):
//   Dashboard ~20s, Workouts ~23s, Detail ~25s, AI scroll ~28s,
//   Statistics ~32s, Progression ~34s, Recovery ~39s, Readiness ~42s, AI Coach ~48s
// Output time = 2 + (source - 0) / 2.0
const enCallouts: CalloutConfig[] = [
  { text: 'Recovery Dashboard', description: 'Track your recovery at a glance', startFrame: 3 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Workout History', startFrame: 5 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Workout Details & AI Analysis', startFrame: 7 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
  { text: 'Training Stats', startFrame: 13 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
  { text: 'Readiness & AI Coach', startFrame: 23 * FPS, durationFrames: 4 * FPS, position: 'bottom' },
]

// fr-FR: raw 86s, trim 10s → 76s usable, 2.7x → 28.1s + 2s intro
// Overhead is larger (~35s), content starts later in output
const frCallouts: CalloutConfig[] = [
  { text: 'Tableau de Récupération', description: 'Suivez votre récupération en un clin d\'œil', startFrame: 3 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Historique d\'Entraînement', startFrame: 5 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Détail & Analyse IA', startFrame: 7 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
  { text: 'Statistiques', startFrame: 13 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
  { text: 'Préparation & Coach IA', startFrame: 23 * FPS, durationFrames: 4 * FPS, position: 'bottom' },
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
          subtitle: 'AI-Powered Running Coach',
          endCardCta: 'Download on the App Store',
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
          subtitle: 'Coach Running propulsé par l\'IA',
          endCardCta: 'Télécharger sur l\'App Store',
        }}
      />
    </>
  )
}
