'use client'

import InsightRunFeatures from './components/HealthAppFeatures'
import InsightRunFooter from './components/HealthAppFooter'
import InsightRunHeader from './components/HealthAppHeader'
import InsightRunHero from './components/HealthAppHero'

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
