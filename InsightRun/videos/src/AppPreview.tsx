import React from 'react'
import {
  AbsoluteFill,
  Sequence,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
  staticFile,
} from 'remotion'
import { Video } from '@remotion/media'
import { LightLeak } from '@remotion/light-leaks'
import { IntroTitle } from './IntroTitle'
import { FeatureCallout } from './FeatureCallout'
import type { AppPreviewProps } from './Root'

export const AppPreview: React.FC<AppPreviewProps> = ({
  videoFile,
  playbackRate,
  trimStartSeconds,
  callouts,
}) => {
  const frame = useCurrentFrame()
  const { fps, durationInFrames } = useVideoConfig()

  // Intro: 2s
  const introFrames = 2 * fps

  // Fade in video after intro
  const videoFadeIn = interpolate(frame, [introFrames, introFrames + 0.5 * fps], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  // Fade out at end
  const videoFadeOut = interpolate(
    frame,
    [durationInFrames - 0.5 * fps, durationInFrames],
    [1, 0],
    { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' },
  )

  // Subtle zoom (ken burns): 1.0 → 1.05 over the full duration
  const scale = interpolate(frame, [introFrames, durationInFrames], [1.0, 1.05], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  return (
    <AbsoluteFill style={{ backgroundColor: 'black' }}>
      {/* Intro title */}
      <Sequence durationInFrames={introFrames + 0.3 * fps} premountFor={fps}>
        <IntroTitle />
      </Sequence>

      {/* Light leak transition from intro to video */}
      <Sequence from={introFrames - 0.3 * fps} durationInFrames={1.2 * fps}>
        <LightLeak seed={2} hueShift={260} />
      </Sequence>

      {/* Main video */}
      <Sequence from={introFrames} premountFor={fps}>
        <AbsoluteFill style={{ opacity: videoFadeIn * videoFadeOut }}>
          <div
            style={{
              width: '100%',
              height: '100%',
              transform: `scale(${scale})`,
              transformOrigin: 'center center',
            }}
          >
            <Video
              src={staticFile(videoFile)}
              playbackRate={playbackRate}
              trimBefore={trimStartSeconds * fps}
              muted
              style={{ width: '100%', height: '100%', objectFit: 'cover' }}
            />
          </div>
        </AbsoluteFill>
      </Sequence>

      {/* Feature callouts */}
      {callouts.map((callout, i) => (
        <Sequence
          key={i}
          from={callout.startFrame}
          durationInFrames={callout.durationFrames}
          premountFor={0.3 * fps}
        >
          <FeatureCallout text={callout.text} position={callout.position} />
        </Sequence>
      ))}
    </AbsoluteFill>
  )
}
