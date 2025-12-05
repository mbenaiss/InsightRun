export default function InsightRunFeatures() {
  const features = [
    {
      id: 1,
      title: 'AI Coach',
      description:
        'Get personalized advice and analysis from advanced AI to help you improve your performance and reach your goals.',
      icon: (
        <svg
          aria-hidden="true"
          className="w-6 h-6"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
          />
        </svg>
      ),
      className: 'lg:col-span-2 bg-gradient-to-br from-primary/10 to-secondary/10',
      iconBg: 'bg-primary/10 text-primary',
    },
    {
      id: 2,
      title: 'Advanced Tracking',
      description:
        'Detailed metrics for distance, pace, heart rate, cadence, power, with seamless HealthKit and Strava integration.',
      icon: (
        <svg
          aria-hidden="true"
          className="w-6 h-6"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M7 12l3-3 3 3 4-4M8 21l4-4 4 4M3 4h18M4 4h16v12a1 1 0 01-1 1H5a1 1 0 01-1-1V4z"
          />
        </svg>
      ),
      className: 'lg:col-span-1 bg-muted/5',
      iconBg: 'bg-blue-500/10 text-blue-500',
    },
    {
      id: 3,
      title: 'Recovery Analysis',
      description:
        'Track your fitness and readiness with daily recovery scores based on HRV, resting heart rate, and sleep quality.',
      icon: (
        <svg aria-hidden="true" className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
          <path d="M11.645 20.91l-.007-.003-.022-.012a15.247 15.247 0 01-.383-.218 25.18 25.18 0 01-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0112 5.052 5.5 5.5 0 0116.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 01-4.244 3.17 15.247 15.247 0 01-.383.219l-.022.012-.007.004-.003.001a.752.752 0 01-.704 0l-.003-.001z" />
        </svg>
      ),
      className: 'lg:col-span-1 bg-muted/5',
      iconBg: 'bg-red-500/10 text-red-500',
    },
    {
      id: 4,
      title: 'Progress Tracking',
      description: 'Visualize your evolution over time with comprehensive performance trends.',
      icon: (
        <svg aria-hidden="true" className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
          <path d="M18.375 2.25c-1.035 0-1.875.84-1.875 1.875v15.75c0 1.035.84 1.875 1.875 1.875h.75c1.035 0 1.875-.84 1.875-1.875V4.125c0-1.036-.84-1.875-1.875-1.875h-.75zM9.75 8.625c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v11.25c0 1.035-.84 1.875-1.875 1.875h-.75a1.875 1.875 0 01-1.875-1.875V8.625zM3 13.125c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v6.75c0 1.035-.84 1.875-1.875 1.875h-.75A1.875 1.875 0 013 19.875v-6.75z" />
        </svg>
      ),
      className: 'lg:col-span-1 bg-muted/5',
      iconBg: 'bg-emerald-500/10 text-emerald-500',
    },
    {
      id: 5,
      title: 'Privacy-First',
      description: 'Your health data stays on your device. No user tracking, no data selling.',
      icon: (
        <svg aria-hidden="true" className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
          <path
            fillRule="evenodd"
            d="M12 1.5a5.25 5.25 0 00-5.25 5.25v3a3 3 0 00-3 3v6.75a3 3 0 003 3h10.5a3 3 0 003-3v-6.75a3 3 0 00-3-3v-3c0-2.9-2.35-5.25-5.25-5.25zm3.75 8.25v-3a3.75 3.75 0 10-7.5 0v3h7.5z"
            clipRule="evenodd"
          />
        </svg>
      ),
      className: 'lg:col-span-1 bg-muted/5',
      iconBg: 'bg-sky-500/10 text-sky-500',
    },
  ]

  return (
    <section id="features" className="py-24 relative">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center max-w-3xl mx-auto mb-16">
          <h2 className="text-3xl md:text-4xl font-bold mb-6 text-foreground">
            Everything you need to run smarter
          </h2>
          <p className="text-lg text-muted-foreground">
            Insight Run combines advanced metrics, AI coaching, and recovery insights to help you
            reach your running goals.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {features.map((feature) => (
            <div
              key={feature.id}
              className={`glass-card p-8 rounded-3xl transition-all duration-300 hover:border-primary/20 hover:bg-muted/50 group ${feature.className}`}
            >
              <div
                className={`w-12 h-12 rounded-2xl flex items-center justify-center mb-6 ${feature.iconBg} group-hover:scale-110 transition-transform duration-300`}
              >
                {feature.icon}
              </div>
              <h3 className="text-xl font-bold text-card-foreground mb-3">{feature.title}</h3>
              <p className="text-muted-foreground leading-relaxed">{feature.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
