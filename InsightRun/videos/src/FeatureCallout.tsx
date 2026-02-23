import React from 'react'
import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { loadFont } from '@remotion/google-fonts/Inter'

const { fontFamily } = loadFont('normal', {
  weights: ['600', '700'],
  subsets: ['latin'],
})

export type CalloutProps = {
  text: string
  description?: string
  position: 'top' | 'bottom'
}

export const FeatureCallout: React.FC<CalloutProps> = ({ text, description, position }) => {
  const frame = useCurrentFrame()
  const { fps, durationInFrames } = useVideoConfig()

  const enter = spring({ frame, fps, config: { damping: 14, stiffness: 180 } })

  const exit = spring({
    frame,
    fps,
    delay: durationInFrames - 0.4 * fps,
    config: { damping: 200 },
  })

  const progress = enter - exit
  const translateY = interpolate(progress, [0, 1], [50, 0])
  const scale = interpolate(progress, [0, 1], [0.92, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })
  const opacity = interpolate(progress, [0, 1], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        [position === 'top' ? 'top' : 'bottom']: position === 'top' ? 200 : 320,
        display: 'flex',
        justifyContent: 'center',
        opacity,
        transform: `translateY(${translateY}px) scale(${scale})`,
      }}
    >
      {/* Outer glow */}
      <div
        style={{
          borderRadius: 36,
          padding: 2,
          background: 'linear-gradient(135deg, rgba(0, 136, 255, 0.6), rgba(0, 200, 255, 0.3), rgba(0, 136, 255, 0.1))',
          boxShadow: '0 8px 40px rgba(0, 136, 255, 0.2)',
          maxWidth: '85%',
        }}
      >
        <div
          style={{
            background: 'rgba(0, 0, 0, 0.8)',
            backdropFilter: 'blur(32px)',
            WebkitBackdropFilter: 'blur(32px)',
            borderRadius: 34,
            padding: '28px 52px',
          }}
        >
          <span
            style={{
              fontFamily,
              fontSize: 60,
              fontWeight: 700,
              color: 'white',
              letterSpacing: -1,
            }}
          >
            {text}
          </span>
          {description && (
            <div
              style={{
                fontFamily,
                fontSize: 36,
                fontWeight: 400,
                color: 'rgba(255, 255, 255, 0.6)',
                marginTop: 8,
                letterSpacing: 0,
              }}
            >
              {description}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
