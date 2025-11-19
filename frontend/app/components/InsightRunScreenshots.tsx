'use client'

import Image from 'next/image'
import { useCallback, useEffect, useRef, useState } from 'react'

const screenshots = [
  {
    id: 'screenshot-01',
    src: '/screenshots/screenshot-01.png',
    title: 'AI Coach',
    description: 'Personalized AI analysis.',
  },
  {
    id: 'screenshot-02',
    src: '/screenshots/screenshot-02.png',
    title: 'Chat',
    description: 'Ask anything about training.',
  },
  {
    id: 'screenshot-03',
    src: '/screenshots/screenshot-03.png',
    title: 'Advanced Metrics',
    description: 'Biomechanics & performance.',
  },
  {
    id: 'screenshot-04',
    src: '/screenshots/screenshot-04.png',
    title: 'History',
    description: 'Track every achievement.',
  },
  {
    id: 'screenshot-05',
    src: '/screenshots/screenshot-05.png',
    title: 'Recovery',
    description: 'HRV & sleep analysis.',
  },
]

export default function InsightRunScreenshots() {
  const [currentSlide, setCurrentSlide] = useState(2)
  const scrollContainerRef = useRef<HTMLDivElement>(null)

  const scrollToSlide = useCallback((index: number) => {
    const container = scrollContainerRef.current
    if (!container) return

    const cardWidth = 320 // width of card
    const gap = 32 // gap

    // With the padding strategy, scrolling to index * (width + gap) centers the item
    const scrollLeft = index * (cardWidth + gap)

    container.scrollTo({
      left: scrollLeft,
      behavior: 'smooth',
    })
    setCurrentSlide(index)
  }, [])

  useEffect(() => {
    // Scroll to the default slide on mount
    scrollToSlide(2)
  }, [scrollToSlide])

  return (
    <section
      id="screenshots"
      className="py-24 bg-gradient-to-b from-background to-muted overflow-hidden"
    >
      <div className="container mx-auto px-4 mb-16 text-center">
        <h2 className="text-3xl md:text-4xl font-bold mb-6 text-foreground">
          Experience Insight Run
        </h2>
        <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
          A beautiful, intuitive interface designed to help you understand and improve your running
          performance.
        </p>
      </div>

      <div className="relative w-full group">
        {/* Fade Edges */}
        <div className="absolute left-0 top-0 bottom-0 w-12 md:w-32 bg-gradient-to-r from-background to-transparent z-20 pointer-events-none" />
        <div className="absolute right-0 top-0 bottom-0 w-12 md:w-32 bg-gradient-to-l from-background to-transparent z-20 pointer-events-none" />

        {/* Carousel */}
        <div
          ref={scrollContainerRef}
          className="flex gap-8 overflow-x-auto pb-12 pt-8 snap-x snap-mandatory scrollbar-hide"
          style={{
            paddingLeft: 'max(1rem, calc(50% - 160px))',
            paddingRight: 'max(1rem, calc(50% - 160px))',
          }}
          onScroll={(e) => {
            // Optional: Update active state on scroll
            const container = e.currentTarget
            const scrollLeft = container.scrollLeft
            const cardWidth = 320 + 32 // card + gap
            // Add half width to find center point of viewport relative to content start
            // Actually with padding strategy, the item is centered when scrollLeft matches its start pos.
            // So closest index is round(scrollLeft / cardWidth)
            const index = Math.round(scrollLeft / cardWidth)

            if (index !== currentSlide && index >= 0 && index < screenshots.length) {
              setCurrentSlide(index)
            }
          }}
        >
          {screenshots.map((screenshot, index) => (
            <button
              type="button"
              key={screenshot.id}
              className="flex-shrink-0 snap-center w-[320px] group/card cursor-pointer transition-all duration-500 appearance-none bg-transparent border-none p-0 text-left outline-none focus:outline-none"
              onClick={() => scrollToSlide(index)}
            >
              <div
                className={`relative rounded-[2.5rem] overflow-hidden border-[4px] border-muted bg-card shadow-2xl transition-all duration-500 ${
                  currentSlide === index
                    ? 'scale-100 border-primary/30 shadow-primary/10 opacity-100'
                    : 'scale-90 opacity-50 hover:opacity-80'
                }`}
              >
                <Image
                  src={screenshot.src}
                  alt={screenshot.title}
                  width={320}
                  height={693}
                  className="w-full h-auto"
                  quality={90}
                />
                <div
                  className={`absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent transition-opacity duration-300 flex flex-col justify-end p-6 text-center ${currentSlide === index ? 'opacity-100' : 'opacity-0 group-hover/card:opacity-100'}`}
                >
                  <h3 className="text-white font-bold text-lg">{screenshot.title}</h3>
                  <p className="text-gray-300 text-sm">{screenshot.description}</p>
                </div>
              </div>
            </button>
          ))}
        </div>

        {/* Indicators */}
        <div className="flex justify-center gap-3 mt-4">
          {screenshots.map((screenshot, index) => (
            <button
              type="button"
              key={`indicator-${screenshot.id}`}
              onClick={() => scrollToSlide(index)}
              className={`h-2 rounded-full transition-all duration-300 ${
                currentSlide === index
                  ? 'w-8 bg-primary'
                  : 'w-2 bg-muted-foreground/30 hover:bg-muted-foreground/50'
              }`}
              aria-label={`Go to slide ${index + 1}`}
            />
          ))}
        </div>
      </div>

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
