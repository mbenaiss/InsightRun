import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { APP_URL } from './lib/constants'
import { PostHogProvider } from './providers/PostHogProvider'
import { ThemeProvider } from './providers/ThemeProvider'

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
  preload: true,
  variable: '--font-inter',
})

const ogImage = {
  url: '/og-image.jpg',
  width: 1200,
  height: 630,
  alt: 'Insight Run: your watch records, Insight Run explains',
}

export const metadata: Metadata = {
  metadataBase: new URL(APP_URL),
  title: 'Insight Run - AI-Powered Running Coach for iOS',
  description:
    'Track your running workouts with advanced metrics, get personalized AI coaching, and optimize your recovery with Insight Run. HealthKit integration for comprehensive performance analysis.',
  keywords:
    'insight run, running app, AI coach, HealthKit, workout tracker, recovery score, iOS running, fitness app, running metrics',
  openGraph: {
    type: 'website',
    title: 'Insight Run - AI-Powered Running Coach for iOS',
    description:
      'Track your running workouts with advanced metrics, get personalized AI coaching, and optimize your recovery.',
    images: [ogImage],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Insight Run - AI-Powered Running Coach for iOS',
    description:
      'Track your running workouts with advanced metrics, get personalized AI coaching, and optimize your recovery.',
    images: [ogImage],
  },
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={`${inter.variable} font-sans antialiased bg-background`}>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          <PostHogProvider>{children}</PostHogProvider>
        </ThemeProvider>
      </body>
    </html>
  )
}
