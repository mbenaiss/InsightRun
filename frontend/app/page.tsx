'use client'

import InsightRunCta from './components/InsightRunCta'
import InsightRunFeatures from './components/InsightRunFeatures'
import InsightRunFooter from './components/InsightRunFooter'
import InsightRunHeader from './components/InsightRunHeader'
import InsightRunHero from './components/InsightRunHero'
import InsightRunPrivacy from './components/InsightRunPrivacy'
import InsightRunTour from './components/InsightRunTour'

export default function Home() {
  return (
    <>
      <InsightRunHeader />
      <main>
        <InsightRunHero />
        <InsightRunFeatures />
        <InsightRunTour />
        <InsightRunPrivacy />
        <InsightRunCta />
      </main>
      <InsightRunFooter />
    </>
  )
}
