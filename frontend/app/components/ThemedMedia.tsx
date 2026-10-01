'use client'

import Image from 'next/image'
import { useTheme } from 'next-themes'
import { useCallback, useEffect, useState } from 'react'

type ThemedImageProps = {
  name: string
  dir: string
  alt: string
  width: number
  height: number
  className?: string
  eager?: boolean
}

// Both files are in the markup so the right one shows before hydration; CSS hides the other theme's file.
export function ThemedImage({
  name,
  dir,
  alt,
  width,
  height,
  className = '',
  eager,
}: ThemedImageProps) {
  return (
    <>
      <Image
        unoptimized
        priority={eager}
        src={`/${dir}/${name}-light.webp`}
        alt={alt}
        width={width}
        height={height}
        className={`${className} block dark:hidden`}
      />
      <Image
        unoptimized
        priority={eager}
        src={`/${dir}/${name}-dark.webp`}
        alt={alt}
        width={width}
        height={height}
        className={`${className} hidden dark:block`}
      />
    </>
  )
}

export function useSiteTheme() {
  const { resolvedTheme } = useTheme()
  const [mounted, setMounted] = useState(false)
  const [reducedMotion, setReducedMotion] = useState(false)

  useEffect(() => {
    setMounted(true)
    setReducedMotion(window.matchMedia('(prefers-reduced-motion: reduce)').matches)
  }, [])

  return {
    mounted,
    reducedMotion,
    theme: resolvedTheme === 'light' ? ('light' as const) : ('dark' as const),
  }
}

export function useAutoplayInView(enabled: boolean) {
  return useCallback(
    (video: HTMLVideoElement | null) => {
      if (!video || !enabled) return
      const observer = new IntersectionObserver(
        ([entry]) => {
          if (entry.isIntersecting) {
            video.play().catch(() => {})
          } else {
            video.pause()
          }
        },
        { threshold: 0.35 }
      )
      observer.observe(video)
      return () => observer.disconnect()
    },
    [enabled]
  )
}
