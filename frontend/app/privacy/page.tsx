import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Privacy Policy - InsightRun',
  description: 'Privacy Policy for InsightRun - AI-Powered Running Coach for iOS',
}

export default function PrivacyPolicy() {
  return (
    <div className="min-h-screen bg-white">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <h1 className="text-4xl font-bold text-gray-900 mb-8">Privacy Policy for InsightRun</h1>

        <div className="prose prose-lg max-w-none">
          <p className="text-gray-600 mb-8">Last updated: October 21, 2025</p>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Data Collection</h2>
            <p className="text-gray-700 mb-4">
              InsightRun reads the following data from Apple HealthKit:
            </p>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
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
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Data Usage</h2>
            <p className="text-gray-700 mb-4">Your health data is:</p>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
              <li>
                <strong>Stored locally on your device</strong> - All your health data remains on
                your iPhone
              </li>
              <li>
                <strong>Never shared with third parties</strong> - We do not sell, rent, or share
                your personal health information
              </li>
              <li>
                <strong>Used only for generating personalized insights</strong> - Data is processed
                to provide you with recovery scores, performance analysis, and training
                recommendations
              </li>
              <li>
                <strong>Processed securely</strong> - All data processing follows Apple's HealthKit
                security guidelines
              </li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">AI Features</h2>
            <p className="text-gray-700 mb-4">When you use the AI assistant:</p>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
              <li>
                Your workout data and metrics are sent to our secure backend server for AI analysis
                via OpenRouter API
              </li>
              <li>No personally identifiable information (name, email, etc.) is transmitted</li>
              <li>Only anonymized workout metrics are sent to the AI service</li>
              <li>AI responses are not stored on our servers</li>
              <li>All communication is encrypted using HTTPS</li>
              <li>
                Rate limiting is applied (100 requests per hour per IP) to prevent abuse and ensure
                fair usage
              </li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Data Storage and Security</h2>
            <p className="text-gray-700 mb-4">We take your privacy seriously:</p>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
              <li>All health data is stored exclusively in Apple's HealthKit on your device</li>
              <li>We do not maintain any databases of user health information</li>
              <li>
                API keys and sensitive credentials are stored securely using Cloudflare Workers
                secrets
              </li>
              <li>All network communications use industry-standard encryption (HTTPS/TLS)</li>
              <li>We implement security best practices following Apple's App Store guidelines</li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">HealthKit Permissions</h2>
            <p className="text-gray-700 mb-4">
              InsightRun requests permission to read specific health data types. You have full
              control over which data types to share:
            </p>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
              <li>You can grant or deny access to individual data types</li>
              <li>You can modify permissions at any time in the Health app settings</li>
              <li>
                The app will function with partial permissions, though some features may be limited
              </li>
              <li>InsightRun does not write or modify any data in HealthKit - it is read-only</li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Third-Party Services</h2>
            <p className="text-gray-700 mb-4">InsightRun integrates with the following services:</p>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
              <li>
                <strong>OpenRouter API</strong> - Used to provide AI-powered coaching and analysis.
                Only anonymized workout metrics are sent.
              </li>
              <li>
                <strong>Cloudflare Workers</strong> - Our backend infrastructure that securely
                handles API requests without storing user data.
              </li>
              <li>
                <strong>Apple HealthKit</strong> - Native iOS framework for accessing health data
                with your permission.
              </li>
            </ul>
            <p className="text-gray-700 mt-4">
              These services are bound by their own privacy policies and our agreements with them
              include strict data protection clauses.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Data Retention</h2>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
              <li>
                Health data remains in Apple HealthKit and is governed by Apple's privacy policy
              </li>
              <li>
                App preferences and settings are stored locally on your device using iOS's
                UserDefaults (not backed up to our servers)
              </li>
              <li>
                We do not retain any user data on our servers beyond the duration of an AI request
              </li>
              <li>
                AI conversation history is stored locally on your device and never synced to the
                cloud
              </li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Data Deletion</h2>
            <p className="text-gray-700 mb-4">You have complete control over your data:</p>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
              <li>You can delete all app data by uninstalling InsightRun from your device</li>
              <li>
                Your HealthKit data remains in the Health app and is not affected by uninstalling
                InsightRun
              </li>
              <li>You can manage HealthKit data directly in the Apple Health app</li>
              <li>
                Since we don't store user data on our servers, there is no remote data to delete
              </li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Children's Privacy</h2>
            <p className="text-gray-700">
              InsightRun is not directed to children under 13. We do not knowingly collect personal
              information from children under 13. If you are a parent or guardian and believe your
              child has provided us with personal information, please contact us.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">
              Changes to This Privacy Policy
            </h2>
            <p className="text-gray-700">
              We may update this Privacy Policy from time to time. We will notify you of any changes
              by posting the new Privacy Policy on this page and updating the "Last updated" date.
              You are advised to review this Privacy Policy periodically for any changes.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Your Rights</h2>
            <p className="text-gray-700 mb-4">You have the right to:</p>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
              <li>
                Access the data we process about you (which is minimal as data stays on your device)
              </li>
              <li>Request deletion of any data we might hold (we don't hold user-specific data)</li>
              <li>Withdraw HealthKit permissions at any time through iOS Settings</li>
              <li>Opt out of AI features by not using the AI assistant</li>
              <li>Export your data through HealthKit's native export functionality</li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">
              International Data Transfers
            </h2>
            <p className="text-gray-700">
              Our backend services (Cloudflare Workers) operate globally. When you use AI features,
              your anonymized workout data may be processed in different geographic regions. All
              data transfers are protected by encryption and comply with applicable data protection
              laws.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Contact Us</h2>
            <p className="text-gray-700 mb-4">
              If you have any questions about this Privacy Policy or our data practices, please
              contact us:
            </p>
            <ul className="list-none space-y-2 text-gray-700">
              <li>
                <strong>Email:</strong> privacy@insightrun.ai
              </li>
              <li>
                <strong>Website:</strong> https://insightrun.ai
              </li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Compliance</h2>
            <p className="text-gray-700">InsightRun complies with:</p>
            <ul className="list-disc pl-6 space-y-2 text-gray-700">
              <li>Apple's App Store Review Guidelines</li>
              <li>Apple's HealthKit Data Usage Guidelines</li>
              <li>GDPR (General Data Protection Regulation) for European users</li>
              <li>CCPA (California Consumer Privacy Act) for California users</li>
              <li>Industry best practices for health data privacy</li>
            </ul>
          </section>

          <div className="mt-12 pt-8 border-t border-gray-200">
            <p className="text-sm text-gray-500">
              This privacy policy is effective as of October 21, 2025 and will remain in effect
              except with respect to any changes in its provisions in the future, which will be in
              effect immediately after being posted on this page.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
