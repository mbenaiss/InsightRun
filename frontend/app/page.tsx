'use client'

import InsightRunFeatures from './components/InsightRunFeatures'
import InsightRunFooter from './components/InsightRunFooter'
import InsightRunHeader from './components/InsightRunHeader'
import InsightRunHero from './components/InsightRunHero'

export default function Home() {
  return (
    <>
      <InsightRunHeader />
      <main>
        <InsightRunHero />
        <InsightRunFeatures />
      </main>
      <InsightRunFooter />
    </>
  )
}
