import Link from 'next/link'

const points = [
  {
    title: 'Your health records stay on your iPhone',
    body: 'Insight Run reads Apple Health on your device. There is no server-side copy of your raw health records.',
  },
  {
    title: 'AI coaching is opt-in',
    body: 'When you turn it on, anonymized workout metrics are sent for analysis, never your name, email or route. You can turn it off any time in Settings.',
  },
  {
    title: 'Advice you can check',
    body: 'Recovery and training recommendations are based on published research, and the sources are listed in the app.',
  },
]

export default function InsightRunPrivacy() {
  return (
    <section id="privacy" className="border-t border-line py-24 lg:py-32">
      <div className="mx-auto max-w-6xl px-6">
        <h2 className="max-w-2xl font-display text-4xl font-extrabold tracking-[-0.035em] sm:text-5xl">
          Your health data, your call
        </h2>
        <div className="mt-14 grid gap-10 md:grid-cols-3 md:gap-0 md:divide-x md:divide-line">
          {points.map((p) => (
            <div key={p.title} className="md:px-8 md:first:pl-0 md:last:pr-0">
              <h3 className="text-lg font-semibold text-foreground">{p.title}</h3>
              <p className="mt-3 leading-relaxed text-muted-foreground">{p.body}</p>
            </div>
          ))}
        </div>
        <Link
          href="/privacy"
          className="mt-12 inline-block font-semibold text-foreground underline decoration-primary decoration-2 underline-offset-[6px] hover:text-primary"
        >
          Read the privacy policy
        </Link>
      </div>
    </section>
  )
}
