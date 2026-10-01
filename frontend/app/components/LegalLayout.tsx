import type { ReactNode } from 'react'
import InsightRunFooter from './InsightRunFooter'
import InsightRunHeader from './InsightRunHeader'

export default function LegalLayout({ children }: { children: ReactNode }) {
  return (
    <>
      <InsightRunHeader />
      <main className="pt-32 pb-24 lg:pt-40">
        <article className="mx-auto max-w-3xl px-6 text-[17px] leading-relaxed">{children}</article>
      </main>
      <InsightRunFooter />
    </>
  )
}
