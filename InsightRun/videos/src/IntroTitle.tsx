import React from 'react'
import {
  AbsoluteFill,
  Img,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  staticFile,
  Easing,
} from 'remotion'
import { loadFont } from '@remotion/google-fonts/Inter'

const { fontFamily } = loadFont('normal', {
  weights: ['400', '700', '800'],
  subsets: ['latin'],
})

export const IntroTitle: React.FC = () => {
  const frame = useCurrentFrame()
  const { fps, durationInFrames } = useVideoConfig()

  const logoScale = spring({ frame, fps, config: { damping: 12, stiffness: 200 } })
  const titleEnter = spring({ frame, fps, delay: 8, config: { damping: 200 } })
  const subtitleEnter = spring({ frame, fps, delay: 16, config: { damping: 200 } })

  const exitProgress = interpolate(
    frame,
    [durationInFrames - 0.5 * fps, durationInFrames],
    [0, 1],
    { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.quad) },
  )

  const globalOpacity = 1 - exitProgress

  return (
    <AbsoluteFill
      style={{
        backgroundColor: 'black',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        opacity: globalOpacity,
      }}
    >
      <Img
        src={staticFile('app-icon.png')}
        style={{
          width: 240,
          height: 240,
          borderRadius: 54,
          transform: `scale(${logoScale})`,
          marginBottom: 50,
          boxShadow: '0 24px 80px rgba(0, 136, 255, 0.5)',
        }}
      />

      <div
        style={{
          fontFamily,
          fontSize: 96,
          fontWeight: 800,
          color: 'white',
          letterSpacing: -3,
          opacity: titleEnter,
          transform: `translateY(${interpolate(titleEnter, [0, 1], [30, 0])}px)`,
        }}
      >
        InsightRun
      </div>

      <div
        style={{
          fontFamily,
          fontSize: 44,
          fontWeight: 400,
          color: 'rgba(255, 255, 255, 0.6)',
          marginTop: 20,
          opacity: subtitleEnter,
          transform: `translateY(${interpolate(subtitleEnter, [0, 1], [20, 0])}px)`,
        }}
      >
        AI-Powered Running Coach
      </div>
    </AbsoluteFill>
  )
}
