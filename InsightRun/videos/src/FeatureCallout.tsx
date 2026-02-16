import React from 'react'
import { useCurrentFrame, useVideoConfig, interpolate, spring } from 'remotion'
import { loadFont } from '@remotion/google-fonts/Inter'

const { fontFamily } = loadFont('normal', {
  weights: ['600', '700'],
  subsets: ['latin'],
})

export type CalloutProps = {
  text: string
  position: 'top' | 'bottom'
}

export const FeatureCallout: React.FC<CalloutProps> = ({ text, position }) => {
  const frame = useCurrentFrame()
  const { fps, durationInFrames } = useVideoConfig()

  const enter = spring({ frame, fps, config: { damping: 200 } })

  const exit = spring({
    frame,
    fps,
    delay: durationInFrames - 0.4 * fps,
    config: { damping: 200 },
  })

  const translateY = interpolate(enter - exit, [0, 1], [60, 0])
  const opacity = interpolate(enter - exit, [0, 1], [0, 1], {
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
        transform: `translateY(${translateY}px)`,
      }}
    >
      <div
        style={{
          background: 'rgba(0, 0, 0, 0.75)',
          backdropFilter: 'blur(24px)',
          WebkitBackdropFilter: 'blur(24px)',
          borderRadius: 32,
          padding: '28px 52px',
          maxWidth: '85%',
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
      </div>
    </div>
  )
}
