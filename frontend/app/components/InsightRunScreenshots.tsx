'use client'

import Image from 'next/image'
import { useCallback, useEffect, useRef, useState } from 'react'

// Constants for dimensions and breakpoints
const MOBILE_BREAKPOINT = 768
const MOBILE_WIDTH = 250
const DESKTOP_WIDTH = 300
const GAP_WIDTH = 32 // Corresponds to gap-8 (8 * 4px = 32px)
const MOBILE_MAX_HEIGHT = 542
const DESKTOP_MAX_HEIGHT = 650

const screenshots = [
  {
    id: 'screenshot-01',
    src: '/screenshots/screenshot-01.png',
    title: 'AI Coach in Your Pocket',
    description: 'Get personalized AI analysis of every workout with detailed insights',
  },
  {
    id: 'screenshot-02',
    src: '/screenshots/screenshot-02.png',
    title: 'Ask Anything, Train Smarter',
    description: 'Chat with your AI coach about training, recovery, and performance',
  },
  {
    id: 'screenshot-03',
    src: '/screenshots/screenshot-03.png',
    title: 'Advanced Metrics for Serious Runners',
    description: 'Track performance, biomechanics, and advanced running metrics',
  },
  {
    id: 'screenshot-04',
    src: '/screenshots/screenshot-04.png',
    title: 'Track Every Run, Every Achievement',
    description: 'Complete workout history with stats and records tracking',
  },
  {
    id: 'screenshot-05',
    src: '/screenshots/screenshot-05.png',
    title: 'Optimize Recovery, Maximize Performance',
    description: 'Daily recovery scores based on HRV, heart rate, and sleep quality',
  },
]

export default function InsightRunScreenshots() {
  const [currentSlide, setCurrentSlide] = useState(0)
  const [isMobile, setIsMobile] = useState(false)
  const carouselRef = useRef<HTMLDivElement>(null)

  // Handle viewport size detection
  useEffect(() => {
    if (typeof window === 'undefined') return

    const updateMobile = () => {
      setIsMobile(window.innerWidth < MOBILE_BREAKPOINT)
    }

    // Set initial value
    updateMobile()

    // Listen for resize events
    window.addEventListener('resize', updateMobile)
    return () => window.removeEventListener('resize', updateMobile)
  }, [])

  // Calculate item width based on viewport
  const getItemWidth = useCallback(() => {
    return isMobile ? MOBILE_WIDTH + GAP_WIDTH : DESKTOP_WIDTH + GAP_WIDTH
  }, [isMobile])

  // Handle scroll events
  useEffect(() => {
    const carousel = carouselRef.current
    if (!carousel) return

    const handleScroll = () => {
      const scrollLeft = carousel.scrollLeft
      const itemWidth = getItemWidth()
      const newSlide = Math.round(scrollLeft / itemWidth)
      setCurrentSlide(Math.min(newSlide, screenshots.length - 1))
    }

    carousel.addEventListener('scroll', handleScroll)
    return () => carousel.removeEventListener('scroll', handleScroll)
  }, [getItemWidth])

  // Navigate to a specific slide
  const scrollToSlide = useCallback(
    (index: number) => {
      const carousel = carouselRef.current
      if (!carousel) return

      const itemWidth = getItemWidth()
      carousel.scrollTo({ left: itemWidth * index, behavior: 'smooth' })
    },
    [getItemWidth]
  )

  // Handle keyboard navigation
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'ArrowLeft' && currentSlide > 0) {
        e.preventDefault()
        scrollToSlide(currentSlide - 1)
      } else if (e.key === 'ArrowRight' && currentSlide < screenshots.length - 1) {
        e.preventDefault()
        scrollToSlide(currentSlide + 1)
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [currentSlide, scrollToSlide])

  return (
    <section
      id="screenshots"
      className="py-20 md:py-32 bg-[#0f172a] relative overflow-hidden"
      aria-label="App Screenshots"
    >
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        {/* Section Header */}
        <div className="text-center max-w-3xl mx-auto mb-16">
          <h2 className="text-4xl md:text-5xl font-bold text-white mb-6">Experience Insight Run</h2>
          <p className="text-xl text-gray-300">
            A beautiful, intuitive interface designed to help you understand and improve your
            running performance.
          </p>
        </div>

        {/* Screenshot Carousel */}
        <div className="relative max-w-7xl mx-auto">
          {/* Gradient fade on edges */}
          <div className="absolute left-0 top-0 bottom-0 w-32 bg-gradient-to-r from-slate-900 to-transparent z-10 pointer-events-none" />
          <div className="absolute right-0 top-0 bottom-0 w-32 bg-gradient-to-l from-slate-900 to-transparent z-10 pointer-events-none" />

          {/* Carousel Container */}
          <div
            ref={carouselRef}
            className="flex gap-8 overflow-x-auto pb-8 snap-x snap-mandatory scrollbar-hide px-4 touch-pan-x"
            style={{ WebkitOverflowScrolling: 'touch' }}
          >
            {screenshots.map((screenshot, _index) => (
              <div
                key={screenshot.id}
                className="flex-shrink-0 snap-center pt-8 w-[250px] md:w-[300px]"
              >
                <Image
                  src={screenshot.src}
                  alt={screenshot.title}
                  width={300}
                  height={650}
                  loading="lazy"
                  quality={85}
                  className={`w-full h-auto max-h-[${MOBILE_MAX_HEIGHT}px] md:max-h-[${DESKTOP_MAX_HEIGHT}px] object-cover drop-shadow-[0_20px_50px_rgba(0,0,0,0.6)] rounded-[2rem]`}
                />
              </div>
            ))}
          </div>

          {/* Scroll Indicator */}
          <div className="flex justify-center gap-2 mt-8" aria-live="polite" aria-atomic="true">
            <span className="sr-only">
              Slide {currentSlide + 1} of {screenshots.length}
            </span>
            {screenshots.map((screenshot, index) => (
              <button
                key={screenshot.id}
                type="button"
                onClick={() => scrollToSlide(index)}
                className={`h-2 rounded-full transition-all duration-300 cursor-pointer ${
                  currentSlide === index ? 'bg-white w-8' : 'bg-white/30 w-2 hover:bg-white/50'
                }`}
                aria-label={`Go to screenshot ${index + 1}: ${screenshot.title}`}
                aria-current={currentSlide === index ? 'true' : 'false'}
              />
            ))}
          </div>
        </div>

        {/* Keyboard navigation hint */}
        <div className="text-center mt-4 text-sm text-gray-500">
          Use arrow keys to navigate between screenshots
        </div>
      </div>

      {/* Add custom CSS to hide scrollbar */}
      <style jsx>{`
        .scrollbar-hide::-webkit-scrollbar {
          display: none;
        }
        .scrollbar-hide {
          -ms-overflow-style: none;
          scrollbar-width: none;
        }
      `}</style>
    </section>
  )
}
