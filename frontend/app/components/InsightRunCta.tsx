import Image from 'next/image'
import { APP_STORE_URL } from '../lib/constants'

export default function InsightRunCta() {
  return (
    <section className="relative overflow-hidden border-t border-line py-28 lg:py-36">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(50%_60%_at_50%_100%,var(--glow),transparent_70%)]"
      />
      <div className="relative mx-auto flex max-w-6xl flex-col items-center px-6 text-center">
        <Image
          src="/app-icon.webp"
          alt=""
          width={88}
          height={88}
          unoptimized
          className="rounded-[20px] shadow-[0_20px_50px_-15px_var(--glow)]"
        />
        <h2 className="mt-8 font-display text-[clamp(2.5rem,6vw,4.5rem)] font-extrabold leading-[1] tracking-[-0.045em]">
          Every run, explained.
        </h2>
        <p className="mt-5 max-w-md text-lg text-muted-foreground">
          Insight Run is available for iPhone on the App Store.
        </p>
        <a
          href={APP_STORE_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-10 rounded-[10px] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-primary"
        >
          <Image
            src="/app-store-badge.svg"
            alt="Download on the App Store"
            width={156}
            height={52}
            className="h-[52px] w-auto"
          />
        </a>
      </div>
    </section>
  )
}
