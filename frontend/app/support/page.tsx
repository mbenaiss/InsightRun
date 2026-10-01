import type { Metadata } from 'next'
import LegalLayout from '@/app/components/LegalLayout'
import {
  APP_NAME,
  APP_URL,
  LAST_UPDATED_DATE,
  MIN_IOS_VERSION,
  SUPPORT_EMAIL,
} from '@/app/lib/constants'

export const metadata: Metadata = {
  title: 'Support - Insight Run',
  description: 'Get support for Insight Run - AI-powered running coach',
  alternates: {
    canonical: `${APP_URL}/support`,
  },
  openGraph: {
    title: 'Support - Insight Run',
    description: 'Get support for Insight Run - AI-powered running coach',
    url: `${APP_URL}/support`,
    siteName: APP_NAME,
    type: 'website',
  },
}

export default function SupportPage() {
  return (
    <LegalLayout>
      <h1 className="mb-12 font-display text-4xl font-extrabold tracking-[-0.035em] text-foreground sm:text-5xl">
        Support
      </h1>
      <div>
        <section className="mb-14" aria-label="Support Overview">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Welcome to Insight Run Support
          </h2>
          <p className="mb-4 text-foreground/80">
            We're here to help you get the most out of your AI-powered running coach. Below you'll
            find answers to common questions and ways to contact us.
          </p>
        </section>

        <section className="mb-14" aria-label="Frequently Asked Questions">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Frequently Asked Questions
          </h2>

          <div className="space-y-6">
            <div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">
                How do I get started with Insight Run?
              </h3>
              <p className="text-foreground/80">
                Download the app from the App Store, grant HealthKit permissions to access your
                workout data, and start getting AI-powered insights about your running performance.
              </p>
            </div>

            <div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">
                What data does Insight Run access?
              </h3>
              <p className="text-foreground/80">
                Insight Run accesses your workout data from Apple HealthKit including distance,
                duration, heart rate, and pace. Your health records stay in Apple Health on your
                iPhone. If you turn on AI coaching, the anonymized metrics needed for an answer are
                sent for analysis. For detailed information, please see our{' '}
                <a
                  href="/privacy"
                  className="font-medium text-foreground underline decoration-primary decoration-2 underline-offset-4 hover:text-primary"
                >
                  Privacy Policy
                </a>
                .
              </p>
            </div>

            <div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">
                How do the AI insights work?
              </h3>
              <p className="text-foreground/80">
                Our AI analyzes your running data to provide personalized insights, training
                recommendations, and performance analysis. The AI uses advanced language models to
                understand your running patterns and provide actionable feedback.
              </p>
            </div>

            <div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">Is my data secure?</h3>
              <p className="text-foreground/80">
                Yes. Your health records stay on your device, and everything sent to our servers is
                encrypted. We never sell your data. AI coaching is opt-in: only with your consent
                are anonymized workout metrics shared with an AI service to generate your coaching,
                and you can turn it off at any time in Settings.
              </p>
            </div>

            <div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">
                What Apple Watch models are supported?
              </h3>
              <p className="text-foreground/80">
                Insight Run works with all Apple Watch models that support HealthKit and workout
                tracking. For the best experience, we recommend Apple Watch Series 4 or newer.
              </p>
            </div>

            <div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">
                How can I delete my data?
              </h3>
              <p className="text-foreground/80">
                Deleting the app removes everything Insight Run stores on your iPhone, including
                your coach conversations. Disconnecting Strava in Settings removes your synchronized
                Strava data from our servers, and your health records stay in Apple Health, where
                you manage them. To delete the pseudonymous data linked to your app identifier,
                email us or see our{' '}
                <a
                  href="/privacy"
                  className="font-medium text-foreground underline decoration-primary decoration-2 underline-offset-4 hover:text-primary"
                >
                  Privacy Policy
                </a>
                .
              </p>
            </div>
          </div>
        </section>

        <section className="mb-14" aria-label="Technical Issues">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Technical Issues
          </h2>

          <div className="space-y-6">
            <div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">
                The app won't connect to HealthKit
              </h3>
              <p className="text-foreground/80">
                Make sure you've granted the necessary permissions in your iPhone Settings:
              </p>
              <ol className="mt-2 list-decimal space-y-1 pl-6 text-foreground/80 marker:text-primary">
                <li>Open Settings on your iPhone</li>
                <li>Scroll down and tap on Insight Run</li>
                <li>Tap on Health</li>
                <li>Enable all requested permissions</li>
              </ol>
            </div>

            <div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">
                Insights are not generating
              </h3>
              <p className="text-foreground/80">
                Ensure you have an active internet connection, as AI insights require connectivity
                to process your data. If the issue persists, try closing and reopening the app.
              </p>
            </div>

            <div>
              <h3 className="mb-2 text-lg font-semibold text-foreground">App crashes or freezes</h3>
              <p className="text-foreground/80">Try the following steps:</p>
              <ol className="mt-2 list-decimal space-y-1 pl-6 text-foreground/80 marker:text-primary">
                <li>Force close the app and reopen it</li>
                <li>Restart your iPhone</li>
                <li>Check for app updates in the App Store</li>
                <li>If the issue persists, contact support</li>
              </ol>
            </div>
          </div>
        </section>

        <section className="mb-14" aria-label="Contact Us">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Contact Us
          </h2>
          <p className="mb-4 text-foreground/80">
            Can't find what you're looking for? We'd love to hear from you!
          </p>

          <div className="rounded-2xl border border-line bg-card p-6">
            <h3 className="mb-3 text-lg font-semibold text-foreground">Email Support</h3>
            <p className="mb-2 text-foreground/80">
              For technical support, feature requests, or general inquiries:
            </p>
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="font-medium text-foreground underline decoration-primary decoration-2 underline-offset-4 hover:text-primary font-semibold"
            >
              {SUPPORT_EMAIL}
            </a>

            <p className="mt-4 text-sm text-muted-foreground">
              We typically respond within 24-48 hours during business days.
            </p>
          </div>
        </section>

        <section className="mb-14" aria-label="System Requirements">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            System Requirements
          </h2>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>iOS {MIN_IOS_VERSION} or later</li>
            <li>iPhone XS, iPhone XR or newer</li>
            <li>Apple Watch (optional, for enhanced tracking)</li>
            <li>Active internet connection for AI insights</li>
            <li>HealthKit access permissions</li>
          </ul>
        </section>

        <section className="mb-14" aria-label="App Updates">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            App Updates
          </h2>
          <p className="text-foreground/80">
            We regularly update Insight Run with new features, improvements, and bug fixes. Enable
            automatic updates in the App Store or check regularly for new versions.
          </p>
        </section>

        <section className="mb-14" aria-label="Feedback">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Feedback
          </h2>
          <p className="mb-4 text-foreground/80">
            Your feedback helps us improve! If you have suggestions for new features or
            improvements, please email us at{' '}
            <a
              href={`mailto:${SUPPORT_EMAIL}`}
              className="font-medium text-foreground underline decoration-primary decoration-2 underline-offset-4 hover:text-primary"
            >
              {SUPPORT_EMAIL}
            </a>
          </p>
          <p className="text-foreground/80">
            Enjoying Insight Run? Please consider leaving a review on the App Store – it helps other
            runners discover our app!
          </p>
        </section>

        <section className="mt-16 border-t border-line pt-8">
          <p className="text-sm text-muted-foreground">Last updated: {LAST_UPDATED_DATE}</p>
        </section>
      </div>
    </LegalLayout>
  )
}
