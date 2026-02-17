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

// en-US: raw 114s, app starts ~12s, content ends ~108s → 96s usable
// 3.7x over 26s video section (30s - 2s intro - 2s endcard)
// Output = 2 + (rawTime - 12) / 3.7
// Dashboard 2-4.5s, Effort 6-7.5s, Sleep 7.5-9s, Readiness 9.5-11s,
// Weekly Summary 11.5-13s, Training Plan 13.5-15.5s, Workouts 16-17s,
// Detail+AI 17-20.5s, Stats 21-23s, Records 24-26s, AI Coach 27-28s
const enCallouts: CalloutConfig[] = [
  { text: 'Recovery Dashboard', description: 'Track your recovery at a glance', startFrame: 2.5 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Effort Analysis', startFrame: 6 * FPS, durationFrames: 1.5 * FPS, position: 'bottom' },
  { text: 'Sleep Analysis', startFrame: 7.5 * FPS, durationFrames: 1.5 * FPS, position: 'bottom' },
  { text: 'Readiness Score', startFrame: 9.5 * FPS, durationFrames: 1.5 * FPS, position: 'bottom' },
  { text: 'Weekly Summary', startFrame: 11.5 * FPS, durationFrames: 1.5 * FPS, position: 'bottom' },
  { text: 'AI Training Plan', startFrame: 13.5 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Workout History', startFrame: 16 * FPS, durationFrames: 1 * FPS, position: 'bottom' },
  { text: 'AI Workout Analysis', startFrame: 17 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
  { text: 'Training Stats', startFrame: 21 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Personal Records', startFrame: 24 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'AI Coach', startFrame: 27 * FPS, durationFrames: 1 * FPS, position: 'bottom' },
]

// fr-FR: raw 112s, app starts ~12s, content ends ~106s → 94s usable
// 3.6x over 26s video section → covers ~93.6s
// Similar flow as EN with French labels
const frCallouts: CalloutConfig[] = [
  { text: 'Tableau de Récupération', description: 'Suivez votre récupération en un clin d\'œil', startFrame: 2.5 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Score d\'Effort', startFrame: 6 * FPS, durationFrames: 1.5 * FPS, position: 'bottom' },
  { text: 'Score de Sommeil', startFrame: 7.5 * FPS, durationFrames: 1.5 * FPS, position: 'bottom' },
  { text: 'Score de Préparation', startFrame: 9.5 * FPS, durationFrames: 1.5 * FPS, position: 'bottom' },
  { text: 'Résumé Hebdomadaire', startFrame: 11.5 * FPS, durationFrames: 1.5 * FPS, position: 'bottom' },
  { text: 'Plan d\'Entraînement IA', startFrame: 13.5 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Historique d\'Entraînement', startFrame: 16 * FPS, durationFrames: 1 * FPS, position: 'bottom' },
  { text: 'Analyse IA du Workout', startFrame: 17 * FPS, durationFrames: 3 * FPS, position: 'bottom' },
  { text: 'Statistiques', startFrame: 21 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Records Personnels', startFrame: 24 * FPS, durationFrames: 2 * FPS, position: 'bottom' },
  { text: 'Coach IA', startFrame: 27 * FPS, durationFrames: 1 * FPS, position: 'bottom' },
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
          playbackRate: 3.7,
          trimStartSeconds: 12,
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
          playbackRate: 3.6,
          trimStartSeconds: 12,
          callouts: frCallouts,
          subtitle: 'Coach Running propulsé par l\'IA',
          endCardCta: 'Télécharger sur l\'App Store',
        }}
      />
    </>
  )
}
