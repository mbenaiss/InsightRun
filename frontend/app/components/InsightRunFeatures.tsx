import { ThemedImage } from './ThemedMedia'

const moments = [
  {
    when: 'Every morning',
    question: 'Should I push today?',
    answer:
      'A readiness score out of 100, built from your heart rate variability, resting heart rate and sleep, and compared with your own baseline rather than an average runner’s.',
    image: 'readiness',
    alt: 'Readiness card showing 82 out of 100, up 6 from yesterday, with HRV 65 ms and resting heart rate 52 bpm',
    height: 570,
  },
  {
    when: 'After every run',
    question: 'How did that session go?',
    answer:
      'A coach verdict in plain words: what the session did, how your heart rate responded, and what to change next time. Route, splits and heart-rate zones are one scroll away.',
    image: 'verdict',
    alt: 'Coach verdict after a 6 × 800 m interval session',
    height: 516,
  },
  {
    when: 'Every week',
    question: 'What should I run next?',
    answer:
      'Set a race and a target time. The plan builds your weeks around it and adjusts them from what you actually ran.',
    image: 'plan',
    alt: 'Plan for the Paris 10K on 8 November, 38 days to go, target time 44:00, 40% done',
    height: 520,
  },
  {
    when: 'Any time',
    question: 'Am I on track?',
    answer:
      'Ask your coach anything about your training. Answers come from your own runs, with the numbers that back them up.',
    image: 'coach',
    alt: 'Coach chat answering whether the runner is on track for a 10K goal',
    height: 806,
    ai: true,
  },
]

const details = [
  {
    title: 'Signals',
    body: 'HRV, resting heart rate, respiratory rate, blood oxygen and cardiac load, each against its normal range.',
  },
  {
    title: 'Run analysis',
    body: 'Route map, heart rate, splits per kilometer and time in each heart-rate zone.',
  },
  {
    title: 'Statistics',
    body: 'Records and monthly trends, so you can see the progress you are making.',
  },
  {
    title: 'Your sources',
    body: 'Apple Watch and other devices through Apple Health, Strava, and Suunto workout files.',
  },
]

export default function InsightRunFeatures() {
  return (
    <section id="features" className="border-t border-line py-24 lg:py-32">
      <div className="mx-auto max-w-6xl px-6">
        <div className="max-w-2xl">
          <h2 className="font-display text-4xl font-extrabold tracking-[-0.035em] sm:text-5xl">
            The questions you ask, answered from your data
          </h2>
          <p className="mt-5 text-lg text-muted-foreground">
            Four moments in a runner’s week, and what Insight Run tells you in each.
          </p>
        </div>

        <ol className="mt-16 lg:mt-20">
          {moments.map((m) => (
            <li
              key={m.image}
              className="grid items-center gap-10 border-t border-line py-14 lg:grid-cols-[1fr_1fr] lg:gap-20"
            >
              <div className="max-w-lg">
                <p className={`text-sm font-semibold ${m.ai ? 'text-secondary' : 'text-primary'}`}>
                  {m.when}
                </p>
                <h3 className="mt-3 font-display text-3xl font-extrabold tracking-[-0.03em] sm:text-4xl">
                  {m.question}
                </h3>
                <p className="mt-4 text-lg leading-relaxed text-muted-foreground">{m.answer}</p>
              </div>
              <div className="mx-auto w-full max-w-[440px] lg:justify-self-end">
                <div
                  className={`overflow-hidden rounded-[26px] ring-1 shadow-[0_30px_80px_-30px_var(--glow)] ${
                    m.ai ? 'ring-secondary/40' : 'ring-line'
                  }`}
                >
                  <ThemedImage
                    name={m.image}
                    dir="ui"
                    alt={m.alt}
                    width={816}
                    height={m.height}
                    className="h-auto w-full"
                  />
                </div>
              </div>
            </li>
          ))}
        </ol>

        <div className="mt-8 border-t border-line pt-16">
          <h3 className="font-display text-2xl font-extrabold tracking-[-0.03em]">
            Also in the app
          </h3>
          <dl className="mt-8 grid gap-x-12 gap-y-8 sm:grid-cols-2 lg:grid-cols-4">
            {details.map((d) => (
              <div key={d.title}>
                <dt className="font-semibold text-foreground">{d.title}</dt>
                <dd className="mt-2 leading-relaxed text-muted-foreground">{d.body}</dd>
              </div>
            ))}
          </dl>
        </div>
      </div>
    </section>
  )
}
