import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { PostHogProvider } from './providers/PostHogProvider'

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
  preload: true,
})

export const metadata: Metadata = {
  metadataBase: new URL('https://insightrun.ai'),
  title: 'InsightRun - AI-Powered Running Coach for iOS',
  description:
    'Track your running workouts with advanced metrics, get personalized AI coaching, and optimize your recovery with InsightRun. HealthKit integration for comprehensive performance analysis.',
  keywords:
    'insightrun, running app, AI coach, HealthKit, workout tracker, recovery score, iOS running, fitness app, running metrics',
  openGraph: {
    type: 'website',
    title: 'InsightRun - AI-Powered Running Coach for iOS',
    description:
      'Track your running workouts with advanced metrics, get personalized AI coaching, and optimize your recovery.',
    images: ['/og-image.jpg'],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'InsightRun - AI-Powered Running Coach for iOS',
    description:
      'Track your running workouts with advanced metrics, get personalized AI coaching, and optimize your recovery.',
    images: ['/og-image.jpg'],
  },
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={`${inter.className} antialiased bg-white`}>
        <PostHogProvider>{children}</PostHogProvider>
      </body>
    </html>
  )
}
