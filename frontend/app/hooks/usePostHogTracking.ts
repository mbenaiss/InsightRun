'use client'

import { usePostHog } from 'posthog-js/react'

export function usePostHogTracking() {
  const posthog = usePostHog()

  const trackButtonClick = (buttonName: string, additionalProperties?: Record<string, unknown>) => {
    posthog?.capture('button_clicked', {
      button_name: buttonName,
      ...additionalProperties,
    })
  }

  const trackLinkClick = (
    linkName: string,
    url: string,
    additionalProperties?: Record<string, unknown>
  ) => {
    posthog?.capture('link_clicked', {
      link_name: linkName,
      url,
      ...additionalProperties,
    })
  }

  const trackVideoPlay = (videoName: string, videoUrl?: string) => {
    posthog?.capture('video_played', {
      video_name: videoName,
      video_url: videoUrl,
    })
  }

  const trackTestimonialView = (testimonialName: string) => {
    posthog?.capture('testimonial_viewed', {
      testimonial_name: testimonialName,
    })
  }

  return {
    trackButtonClick,
    trackLinkClick,
    trackVideoPlay,
    trackTestimonialView,
  }
}
