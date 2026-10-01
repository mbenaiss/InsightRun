import type { Metadata } from 'next'
import LegalLayout from '@/app/components/LegalLayout'
import { APP_NAME, APP_URL, PRIVACY_LAST_UPDATED_DATE, SUPPORT_EMAIL } from '@/app/lib/constants'

export const metadata: Metadata = {
  title: 'Privacy Policy - Insight Run',
  description: 'Privacy Policy for Insight Run - AI-Powered Running Coach for iOS',
  alternates: {
    canonical: `${APP_URL}/privacy`,
  },
  openGraph: {
    title: 'Privacy Policy - Insight Run',
    description: 'Privacy Policy for Insight Run - AI-powered running coach',
    url: `${APP_URL}/privacy`,
    siteName: APP_NAME,
    type: 'website',
  },
}

export default function PrivacyPolicy() {
  return (
    <LegalLayout>
      <h1 className="mb-12 font-display text-4xl font-extrabold tracking-[-0.035em] text-foreground sm:text-5xl">
        Privacy Policy for Insight Run
      </h1>
      <div>
        <p className="mb-12 text-muted-foreground">Last updated: {PRIVACY_LAST_UPDATED_DATE}</p>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Data Collection
          </h2>
          <p className="mb-4 text-foreground/80">
            Insight Run reads the following data from Apple HealthKit:
          </p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>Running workouts (distance, duration, heart rate, pace, cadence)</li>
            <li>
              Advanced running metrics (power, stride length, ground contact time, vertical
              oscillation)
            </li>
            <li>Sleep data (duration, quality)</li>
            <li>Heart rate variability (HRV)</li>
            <li>Body metrics (weight, body mass index)</li>
            <li>VO2 Max estimates</li>
            <li>Resting and walking heart rate</li>
            <li>Respiratory rate</li>
          </ul>
          <p className="my-4 text-foreground/80">
            When you connect your Strava account (optional):
          </p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>Activity data (workouts, routes, performance metrics)</li>
            <li>Profile information (athlete name, avatar)</li>
            <li>Activity statistics and achievements</li>
          </ul>
          <p className="my-4 text-foreground/80">
            To operate subscriptions and improve the app, Insight Run also processes:
          </p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              A randomly generated account identifier used for entitlements, rate limiting, and
              analytics
            </li>
            <li>Subscription status and purchase history processed by our subscription provider</li>
            <li>
              Product interactions and technical diagnostics processed by our analytics provider,
              including app version, device model, operating system version, and locale
            </li>
            <li>
              An approximate location (country and city) derived by our analytics provider, hosted
              in the European Union, from your device's IP address. The provider receives the IP
              address with each analytics event, uses it only to derive this approximate location,
              and does not store the IP address.
            </li>
          </ul>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Data Usage
          </h2>
          <p className="mb-4 text-foreground/80">Your health data is:</p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              <strong>Stored locally on your device</strong> - HealthKit data remains on your iPhone
              except for the workout metrics sent for an AI request with your explicit consent and
              optional Strava data described below
            </li>
            <li>
              <strong>Never sold or rented</strong> - We do not sell, rent, or trade your personal
              health information
            </li>
            <li>
              <strong>Shared with AI services only with your explicit consent</strong> - When you
              enable AI coaching, anonymized workout metrics are sent through our backend server to
              a third-party AI service for analysis. See the "AI Features and Data Processing"
              section below for full details.
            </li>
            <li>
              <strong>Used only for generating personalized insights</strong> - Data is processed to
              provide you with recovery scores, performance analysis, and training recommendations
            </li>
            <li>
              <strong>Processed securely</strong> - All data processing follows Apple's HealthKit
              security guidelines
            </li>
          </ul>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            AI Features and Data Processing
          </h2>
          <p className="mb-4 text-foreground/80">
            Insight Run offers AI-powered coaching features. When you enable AI coaching and provide
            your explicit consent, the following data processing occurs:
          </p>

          <h3 className="mt-8 mb-3 text-lg font-semibold text-foreground">
            Data sent to the AI service
          </h3>
          <p className="mb-4 text-foreground/80">
            The following categories of health and workout data may be included in AI analysis
            requests:
          </p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              <strong>Workout metrics</strong> - Distance, duration, pace, cadence, calories burned
            </li>
            <li>
              <strong>Heart rate data</strong> - Average, max, and resting heart rate during
              workouts
            </li>
            <li>
              <strong>Recovery and HRV</strong> - Heart rate variability, recovery scores, and
              trends
            </li>
            <li>
              <strong>Sleep data</strong> - Sleep duration and quality metrics
            </li>
            <li>
              <strong>Health profile</strong> - VO2 Max estimates, body metrics (weight, BMI),
              respiratory rate
            </li>
            <li>
              <strong>Mobility and performance</strong> - Running power, stride length, ground
              contact time, vertical oscillation
            </li>
          </ul>

          <h3 className="mt-8 mb-3 text-lg font-semibold text-foreground">How data is processed</h3>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>Your anonymized workout data is sent from the app to our secure backend server</li>
            <li>Our backend forwards the anonymized data to a third-party AI routing service</li>
            <li>
              The routing service sends the request to a large language model from an AI provider
            </li>
            <li>The AI model generates personalized coaching insights and returns them to you</li>
          </ul>

          <h3 className="mt-8 mb-3 text-lg font-semibold text-foreground">Data protection</h3>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              AI requests do not contain your name, email address, device identifier, or route
              coordinates. Text you enter in the AI chat is transmitted as part of the request.
            </li>
            <li>
              The app sends a random, pseudonymous installation identifier to our own backend, which
              uses it to enforce usage quotas and prevent abuse, to link your Strava connection to
              your installation, and to measure AI feature usage in our analytics. This identifier
              is not forwarded to the AI routing service or the AI model providers.
            </li>
            <li>
              Data is not permanently stored by the AI routing service or the AI model providers —
              it is used only to generate a response
            </li>
            <li>Your data is never sold, rented, or used for advertising purposes</li>
            <li>AI responses and conversation history are not stored on our servers</li>
            <li>All communication is encrypted in transit using HTTPS/TLS</li>
            <li>
              Rate limiting is applied (a limited number of requests per hour) to prevent abuse and
              ensure fair usage
            </li>
          </ul>

          <h3 className="mt-8 mb-3 text-lg font-semibold text-foreground">Your consent</h3>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              AI coaching features are <strong>opt-in only</strong> — your health data is never sent
              to any AI service without your explicit consent
            </li>
            <li>
              You will be asked to review and accept the data sharing terms before AI features are
              activated
            </li>
            <li>
              You can <strong>revoke your consent at any time</strong> from the app settings, which
              will immediately stop all data sharing with the AI service
            </li>
            <li>Revoking consent does not affect the health data stored locally on your device</li>
          </ul>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Data Storage and Security
          </h2>
          <p className="mb-4 text-foreground/80">We take your privacy seriously:</p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              Source HealthKit records remain in Apple Health on your device. Selected metrics are
              transmitted only when needed for an AI request and with your explicit consent.
            </li>
            <li>
              We do not maintain a server-side database of raw HealthKit records. Optional Strava
              synchronization data, pseudonymous analytics, and subscription records are handled as
              described in this policy.
            </li>
            <li>All network communications use industry-standard encryption (HTTPS/TLS)</li>
            <li>We implement security best practices following Apple's App Store guidelines</li>
          </ul>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            HealthKit Permissions
          </h2>
          <p className="mb-4 text-foreground/80">
            Insight Run requests permission to read specific health data types and, when you
            explicitly import a compatible workout file, to add that workout to HealthKit. You have
            full control over which data types to share:
          </p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>You can grant or deny access to individual data types</li>
            <li>You can modify permissions at any time in the Health app settings</li>
            <li>
              The app will function with partial permissions, though some features may be limited
            </li>
            <li>
              Insight Run does not modify existing HealthKit records. It only writes a workout when
              you explicitly choose to import it.
            </li>
          </ul>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Third-Party Services
          </h2>
          <p className="mb-4 text-foreground/80">
            Insight Run integrates with the following services:
          </p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              <strong>Strava</strong> - Optional integration to synchronize your activities and
              access detailed workout data. When connected, we access only the data you authorize
              through Strava's OAuth flow. All Strava data handling complies with Strava's API
              Agreement and Brand Guidelines.
            </li>
            <li>
              <strong>AI routing service</strong> - Third-party AI API routing service used to
              provide AI-powered coaching and analysis. It forwards requests to large language
              models from established AI providers. Only anonymized workout metrics are sent. Its
              data handling is governed by its privacy policy and our data processing agreements,
              which ensure equivalent protection for your data.
            </li>
            <li>
              <strong>Cloud hosting provider</strong> - Runs our backend infrastructure, which
              securely handles API requests between the app and AI services and stores optional
              Strava synchronization data.
            </li>
            <li>
              <strong>Apple HealthKit</strong> - Native iOS framework for accessing health data with
              your permission.
            </li>
            <li>
              <strong>Analytics provider</strong> (hosted in the European Union) - Processes a
              pseudonymous account identifier, product interactions, and technical diagnostics for
              analytics and app functionality. It receives your device's IP address with each event,
              uses it only to derive an approximate location (country and city), and does not store
              the IP address. This data is not used for advertising or cross-app tracking.
            </li>
            <li>
              <strong>Subscription provider</strong> - Processes a pseudonymous account identifier,
              subscription status, and purchase history to validate purchases, unlock entitlements,
              prevent fraud, and provide subscription analytics. Payment card details are handled by
              Apple and are never available to Insight Run or this provider.
            </li>
          </ul>
          <p className="mt-4 text-foreground/80">
            These services are bound by their own privacy policies and our agreements with them
            include strict data protection clauses.
          </p>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Data Retention
          </h2>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              Health data remains in Apple HealthKit and is governed by Apple's privacy policy
            </li>
            <li>
              Optional Strava activities and authentication tokens are stored securely on our
              backend infrastructure until you disconnect Strava, which removes the associated
              server-side synchronization data.
            </li>
            <li>
              App preferences and settings are stored locally on your device using iOS's
              UserDefaults (not backed up to our servers)
            </li>
            <li>
              Health and workout metrics sent for an AI request are not retained by our backend
            </li>
            <li>
              Our analytics and subscription providers retain pseudonymous analytics and
              subscription records under their respective retention policies
            </li>
            <li>
              AI conversation history is stored locally on your device and never synced to the cloud
            </li>
          </ul>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Data Deletion
          </h2>
          <p className="mb-4 text-foreground/80">You have complete control over your data:</p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              You can delete locally stored app data by uninstalling Insight Run from your device
            </li>
            <li>
              You can disconnect your Strava account at any time from the app settings, which will
              remove all cached Strava data
            </li>
            <li>
              Your HealthKit data remains in the Health app and is not affected by uninstalling
              Insight Run
            </li>
            <li>You can manage HealthKit data directly in the Apple Health app</li>
            <li>
              You can contact us at {SUPPORT_EMAIL} to request deletion of pseudonymous analytics or
              subscription data associated with your app identifier
            </li>
          </ul>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Children's Privacy
          </h2>
          <p className="text-foreground/80">
            Insight Run is not directed to children under 13. We do not knowingly collect personal
            information from children under 13. If you are a parent or guardian and believe your
            child has provided us with personal information, please contact us.
          </p>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Changes to This Privacy Policy
          </h2>
          <p className="text-foreground/80">
            We may update this Privacy Policy from time to time. We will notify you of any changes
            by posting the new Privacy Policy on this page and updating the "Last updated" date. You
            are advised to review this Privacy Policy periodically for any changes.
          </p>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Your Rights
          </h2>
          <p className="mb-4 text-foreground/80">You have the right to:</p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>
              Access the data we process about you (which is minimal as data stays on your device)
            </li>
            <li>Request deletion of pseudonymous data associated with your app identifier</li>
            <li>Withdraw HealthKit permissions at any time through iOS Settings</li>
            <li>
              Revoke AI data sharing consent at any time in the app settings, immediately stopping
              all data transmission to the AI service
            </li>
            <li>Opt out of AI features entirely by not enabling AI coaching</li>
            <li>Export your data through HealthKit's native export functionality</li>
          </ul>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            International Data Transfers
          </h2>
          <p className="text-foreground/80">
            Our backend services operate globally. When you use AI features, your anonymized workout
            data may be processed in different geographic regions. All data transfers are protected
            by encryption and comply with applicable data protection laws.
          </p>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Contact Us
          </h2>
          <p className="mb-4 text-foreground/80">
            If you have any questions about this Privacy Policy or our data practices, please
            contact us:
          </p>
          <ul className="list-none space-y-2 text-foreground/80">
            <li>
              <strong>Email:</strong> {SUPPORT_EMAIL}
            </li>
            <li>
              <strong>Website:</strong> {APP_URL}
            </li>
          </ul>
        </section>

        <section className="mb-14">
          <h2 className="mb-4 font-display text-2xl font-extrabold tracking-[-0.025em] text-foreground">
            Compliance
          </h2>
          <p className="text-foreground/80">Insight Run complies with:</p>
          <ul className="list-disc space-y-2 pl-6 text-foreground/80 marker:text-primary">
            <li>Apple's App Store Review Guidelines</li>
            <li>Apple's HealthKit Data Usage Guidelines</li>
            <li>GDPR (General Data Protection Regulation) for European users</li>
            <li>CCPA (California Consumer Privacy Act) for California users</li>
            <li>Industry best practices for health data privacy</li>
          </ul>
        </section>

        <div className="mt-16 border-t border-line pt-8">
          <p className="text-sm text-muted-foreground">
            This privacy policy is effective as of {PRIVACY_LAST_UPDATED_DATE} and will remain in
            effect except with respect to any changes in its provisions in the future, which will be
            in effect immediately after being posted on this page.
          </p>
        </div>
      </div>
    </LegalLayout>
  )
}
