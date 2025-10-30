'use client'

export default function InsightRunScreenshots() {
  return (
    <section id="screenshots" className="py-20 md:py-32 bg-white relative overflow-hidden">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        {/* Section Header */}
        <div className="text-center max-w-3xl mx-auto mb-16">
          <h2 className="text-4xl md:text-5xl font-bold text-[#1a2942] mb-6">
            Experience InsightRun
          </h2>
          <p className="text-xl text-gray-600">
            A beautiful, intuitive interface designed to help you understand and improve your
            running performance.
          </p>
        </div>

        {/* Screenshot Carousel Placeholder */}
        <div className="relative max-w-7xl mx-auto">
          {/* Gradient fade on edges */}
          <div className="absolute left-0 top-0 bottom-0 w-32 bg-gradient-to-r from-white to-transparent z-10" />
          <div className="absolute right-0 top-0 bottom-0 w-32 bg-gradient-to-l from-white to-transparent z-10" />

          {/* Carousel Container */}
          <div className="flex gap-8 overflow-x-auto pb-8 snap-x snap-mandatory scrollbar-hide">
            {/* Screenshot 1 - Placeholder */}
            <div className="flex-shrink-0 snap-center">
              <div className="relative bg-[#1a2942] rounded-[3rem] p-4 shadow-2xl w-[300px]">
                <div className="bg-gradient-to-br from-[#fdf8f3] to-white rounded-[2.5rem] overflow-hidden aspect-[9/19.5]">
                  <div className="h-full flex flex-col items-center justify-center p-8 bg-gradient-to-br from-[#0094FF]/10 to-[#64B0FF]/10">
                    <div className="w-20 h-20 bg-gradient-to-br from-[#0094FF] to-[#64B0FF] rounded-3xl mb-4 flex items-center justify-center">
                      <svg
                        className="w-10 h-10 text-white"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                        role="img"
                        aria-label="Dashboard icon"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M13 10V3L4 14h7v7l9-11h-7z"
                        />
                      </svg>
                    </div>
                    <h3 className="text-lg font-bold text-[#1a2942] mb-2">Dashboard</h3>
                    <p className="text-sm text-gray-600 text-center">
                      Your complete running overview at a glance
                    </p>
                  </div>
                </div>
                {/* Notch */}
                <div className="absolute top-7 left-1/2 transform -translate-x-1/2 w-28 h-6 bg-[#1a2942] rounded-full" />
              </div>
            </div>

            {/* Screenshot 2 - Placeholder */}
            <div className="flex-shrink-0 snap-center">
              <div className="relative bg-[#1a2942] rounded-[3rem] p-4 shadow-2xl w-[300px]">
                <div className="bg-gradient-to-br from-[#fdf8f3] to-white rounded-[2.5rem] overflow-hidden aspect-[9/19.5]">
                  <div className="h-full flex flex-col items-center justify-center p-8 bg-gradient-to-br from-[#0094FF]/10 to-[#005A99]/10">
                    <div className="w-20 h-20 bg-gradient-to-br from-[#0094FF] to-[#005A99] rounded-3xl mb-4 flex items-center justify-center">
                      <svg
                        className="w-10 h-10 text-white"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                        role="img"
                        aria-label="Analytics icon"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                        />
                      </svg>
                    </div>
                    <h3 className="text-lg font-bold text-[#1a2942] mb-2">Analytics</h3>
                    <p className="text-sm text-gray-600 text-center">
                      Deep insights into your performance
                    </p>
                  </div>
                </div>
                {/* Notch */}
                <div className="absolute top-7 left-1/2 transform -translate-x-1/2 w-28 h-6 bg-[#1a2942] rounded-full" />
              </div>
            </div>

            {/* Screenshot 3 - Placeholder */}
            <div className="flex-shrink-0 snap-center">
              <div className="relative bg-[#1a2942] rounded-[3rem] p-4 shadow-2xl w-[300px]">
                <div className="bg-gradient-to-br from-[#fdf8f3] to-white rounded-[2.5rem] overflow-hidden aspect-[9/19.5]">
                  <div className="h-full flex flex-col items-center justify-center p-8 bg-gradient-to-br from-[#64B0FF]/10 to-[#0094FF]/10">
                    <div className="w-20 h-20 bg-gradient-to-br from-[#64B0FF] to-[#0094FF] rounded-3xl mb-4 flex items-center justify-center">
                      <svg
                        className="w-10 h-10 text-white"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                        role="img"
                        aria-label="Recovery icon"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                        />
                      </svg>
                    </div>
                    <h3 className="text-lg font-bold text-[#1a2942] mb-2">Recovery</h3>
                    <p className="text-sm text-gray-600 text-center">
                      Track your readiness to train
                    </p>
                  </div>
                </div>
                {/* Notch */}
                <div className="absolute top-7 left-1/2 transform -translate-x-1/2 w-28 h-6 bg-[#1a2942] rounded-full" />
              </div>
            </div>

            {/* Screenshot 4 - Placeholder */}
            <div className="flex-shrink-0 snap-center">
              <div className="relative bg-[#1a2942] rounded-[3rem] p-4 shadow-2xl w-[300px]">
                <div className="bg-gradient-to-br from-[#fdf8f3] to-white rounded-[2.5rem] overflow-hidden aspect-[9/19.5]">
                  <div className="h-full flex flex-col items-center justify-center p-8 bg-gradient-to-br from-[#0094FF]/10 to-[#1a2942]/10">
                    <div className="w-20 h-20 bg-gradient-to-br from-[#0094FF] to-[#1a2942] rounded-3xl mb-4 flex items-center justify-center">
                      <svg
                        className="w-10 h-10 text-white"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                        role="img"
                        aria-label="AI Insights icon"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
                        />
                      </svg>
                    </div>
                    <h3 className="text-lg font-bold text-[#1a2942] mb-2">AI Insights</h3>
                    <p className="text-sm text-gray-600 text-center">
                      Personalized coaching recommendations
                    </p>
                  </div>
                </div>
                {/* Notch */}
                <div className="absolute top-7 left-1/2 transform -translate-x-1/2 w-28 h-6 bg-[#1a2942] rounded-full" />
              </div>
            </div>
          </div>

          {/* Scroll Indicator */}
          <div className="flex justify-center gap-2 mt-8">
            <div className="w-2 h-2 rounded-full bg-[#0094FF]" />
            <div className="w-2 h-2 rounded-full bg-gray-300" />
            <div className="w-2 h-2 rounded-full bg-gray-300" />
            <div className="w-2 h-2 rounded-full bg-gray-300" />
          </div>
        </div>

        {/* Call to Action */}
        <div className="text-center mt-16">
          <p className="text-gray-600 mb-6">
            Replace these placeholders with your actual app screenshots to showcase the real
            experience.
          </p>
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
