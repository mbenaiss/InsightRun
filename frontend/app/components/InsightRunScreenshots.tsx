'use client'

import Image from 'next/image'
import { useEffect, useRef, useState } from 'react'

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
  const carouselRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const carousel = carouselRef.current
    if (!carousel) return

    const handleScroll = () => {
      const scrollLeft = carousel.scrollLeft
      // Each screenshot width + gap (mobile: 250px + 32px, desktop: 300px + 32px)
      const isMobile = window.innerWidth < 768
      const itemWidth = isMobile ? 250 + 32 : 300 + 32
      const newSlide = Math.round(scrollLeft / itemWidth)
      setCurrentSlide(Math.min(newSlide, screenshots.length - 1))
    }

    carousel.addEventListener('scroll', handleScroll)
    return () => carousel.removeEventListener('scroll', handleScroll)
  }, [])

  return (
    <section id="screenshots" className="py-20 md:py-32 bg-[#0f172a] relative overflow-hidden">
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
            {screenshots.map((screenshot) => (
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
                  className="w-full h-auto max-h-[542px] md:max-h-[650px] object-cover drop-shadow-[0_20px_50px_rgba(0,0,0,0.6)] rounded-[2rem]"
                />
              </div>
            ))}
          </div>

          {/* Scroll Indicator */}
          <div className="flex justify-center gap-2 mt-8">
            {screenshots.map((screenshot, index) => (
              <button
                key={screenshot.id}
                type="button"
                onClick={() => {
                  const carousel = carouselRef.current
                  if (carousel) {
                    const isMobile = window.innerWidth < 768
                    const itemWidth = isMobile ? 250 + 32 : 300 + 32 // width + gap
                    carousel.scrollTo({ left: itemWidth * index, behavior: 'smooth' })
                  }
                }}
                className={`h-2 rounded-full transition-all duration-300 cursor-pointer ${
                  currentSlide === index ? 'bg-white w-8' : 'bg-white/30 w-2 hover:bg-white/50'
                }`}
                aria-label={`Go to screenshot ${index + 1}: ${screenshot.title}`}
              />
            ))}
          </div>
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
