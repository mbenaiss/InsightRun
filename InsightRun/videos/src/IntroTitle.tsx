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

const ACCENT_COLOR = 'rgba(0, 136, 255, 1)'

export const IntroTitle: React.FC<{ subtitle: string }> = ({ subtitle }) => {
  const frame = useCurrentFrame()
  const { fps, durationInFrames } = useVideoConfig()

  const logoScale = spring({ frame, fps, config: { damping: 12, stiffness: 200 } })
  const titleEnter = spring({ frame, fps, delay: 8, config: { damping: 14, stiffness: 180 } })
  const subtitleEnter = spring({ frame, fps, delay: 16, config: { damping: 200 } })

  // Pulsing glow on logo
  const glowPulse = interpolate(frame, [0, 1.5 * fps], [0.4, 0.7], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.inOut(Easing.sin),
  })

  const exitProgress = interpolate(
    frame,
    [durationInFrames - 0.5 * fps, durationInFrames],
    [0, 1],
    { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: Easing.inOut(Easing.quad) },
  )

  const globalOpacity = 1 - exitProgress
  const globalScale = interpolate(exitProgress, [0, 1], [1, 0.95])

  return (
    <AbsoluteFill
      style={{
        backgroundColor: 'black',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        opacity: globalOpacity,
        transform: `scale(${globalScale})`,
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
          boxShadow: `0 24px 80px rgba(0, 136, 255, ${glowPulse}), 0 0 120px rgba(0, 136, 255, ${glowPulse * 0.3})`,
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
          transform: `translateY(${interpolate(titleEnter, [0, 1], [40, 0])}px)`,
        }}
      >
        Insight Run
      </div>

      {/* Accent line */}
      <div
        style={{
          width: interpolate(titleEnter, [0, 1], [0, 120]),
          height: 4,
          borderRadius: 2,
          background: `linear-gradient(90deg, transparent, ${ACCENT_COLOR}, transparent)`,
          marginTop: 24,
          opacity: titleEnter,
        }}
      />

      <div
        style={{
          fontFamily,
          fontSize: 44,
          fontWeight: 400,
          color: 'rgba(255, 255, 255, 0.6)',
          marginTop: 24,
          opacity: subtitleEnter,
          transform: `translateY(${interpolate(subtitleEnter, [0, 1], [20, 0])}px)`,
        }}
      >
        {subtitle}
      </div>
    </AbsoluteFill>
  )
}
