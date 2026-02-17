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
import { EndCard } from './EndCard'
import { FeatureCallout } from './FeatureCallout'
import type { AppPreviewProps } from './Root'

export const AppPreview: React.FC<AppPreviewProps> = ({
  videoFile,
  playbackRate,
  trimStartSeconds,
  callouts,
  subtitle,
  endCardCta,
}) => {
  const frame = useCurrentFrame()
  const { fps, durationInFrames } = useVideoConfig()

  // Intro: 2s
  const introFrames = 2 * fps

  // End card: last 2s
  const endCardFrames = 2 * fps
  const endCardStart = durationInFrames - endCardFrames

  // Fade in video after intro
  const videoFadeIn = interpolate(frame, [introFrames, introFrames + 0.5 * fps], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  // Fade out video before end card
  const videoFadeOut = interpolate(
    frame,
    [endCardStart - 0.5 * fps, endCardStart],
    [1, 0],
    { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' },
  )

  // Subtle zoom (ken burns): 1.0 → 1.05 over the video section
  const scale = interpolate(frame, [introFrames, endCardStart], [1.0, 1.05], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  })

  return (
    <AbsoluteFill style={{ backgroundColor: 'black' }}>
      {/* Intro title */}
      <Sequence durationInFrames={introFrames + 0.3 * fps} premountFor={fps}>
        <IntroTitle subtitle={subtitle} />
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
          <FeatureCallout text={callout.text} description={callout.description} position={callout.position} />
        </Sequence>
      ))}

      {/* Light leak transition to end card */}
      <Sequence from={endCardStart - 0.4 * fps} durationInFrames={1 * fps}>
        <LightLeak seed={5} hueShift={240} />
      </Sequence>

      {/* End card */}
      <Sequence from={endCardStart} durationInFrames={endCardFrames} premountFor={0.5 * fps}>
        <EndCard cta={endCardCta} />
      </Sequence>
    </AbsoluteFill>
  )
}
