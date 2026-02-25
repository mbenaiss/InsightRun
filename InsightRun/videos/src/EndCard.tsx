import React from 'react'
import {
  AbsoluteFill,
  Img,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  staticFile,
} from 'remotion'
import { loadFont } from '@remotion/google-fonts/Inter'

const { fontFamily } = loadFont('normal', {
  weights: ['400', '600', '800'],
  subsets: ['latin'],
})

export const EndCard: React.FC<{ cta: string }> = ({ cta }) => {
  const frame = useCurrentFrame()
  const { fps } = useVideoConfig()

  const logoScale = spring({ frame, fps, config: { damping: 12, stiffness: 200 } })
  const textEnter = spring({ frame, fps, delay: 6, config: { damping: 200 } })
  const ctaEnter = spring({ frame, fps, delay: 14, config: { damping: 14, stiffness: 160 } })

  const glowOpacity = interpolate(frame, [0, 1 * fps], [0, 0.5], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  return (
    <AbsoluteFill
      style={{
        backgroundColor: 'black',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      {/* Background glow */}
      <div
        style={{
          position: 'absolute',
          width: 600,
          height: 600,
          borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(0, 136, 255, 0.3) 0%, transparent 70%)',
          opacity: glowOpacity,
          filter: 'blur(60px)',
        }}
      />

      <Img
        src={staticFile('app-icon.png')}
        style={{
          width: 200,
          height: 200,
          borderRadius: 46,
          transform: `scale(${logoScale})`,
          marginBottom: 44,
          boxShadow: '0 20px 60px rgba(0, 136, 255, 0.4)',
        }}
      />

      <div
        style={{
          fontFamily,
          fontSize: 84,
          fontWeight: 800,
          color: 'white',
          letterSpacing: -2,
          opacity: textEnter,
          transform: `translateY(${interpolate(textEnter, [0, 1], [20, 0])}px)`,
        }}
      >
        Insight Run
      </div>

      <div
        style={{
          fontFamily,
          fontSize: 40,
          fontWeight: 400,
          color: 'rgba(255, 255, 255, 0.5)',
          marginTop: 40,
          opacity: ctaEnter,
          transform: `translateY(${interpolate(ctaEnter, [0, 1], [16, 0])}px)`,
        }}
      >
        {cta}
      </div>
    </AbsoluteFill>
  )
}
