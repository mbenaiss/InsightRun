import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Support - Insight Run',
  description: 'Get support for Insight Run - AI-powered running coach',
}

export default function SupportPage() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-blue-50 to-white">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <h1 className="text-4xl font-bold text-gray-900 mb-8">Support</h1>

        <div className="prose prose-blue max-w-none">
          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Welcome to Insight Run Support</h2>
            <p className="text-gray-700 mb-4">
              We're here to help you get the most out of your AI-powered running coach. Below you'll find answers to common questions and ways to contact us.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Frequently Asked Questions</h2>

            <div className="space-y-6">
              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">How do I get started with Insight Run?</h3>
                <p className="text-gray-700">
                  Download the app from the App Store, grant HealthKit permissions to access your workout data, and start getting AI-powered insights about your running performance.
                </p>
              </div>

              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">What data does Insight Run access?</h3>
                <p className="text-gray-700">
                  Insight Run accesses your workout data from Apple HealthKit including distance, duration, heart rate, and pace. All data is processed locally on your device. For detailed information, please see our <a href="/privacy" className="text-blue-600 hover:text-blue-800 underline">Privacy Policy</a>.
                </p>
              </div>

              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">How do the AI insights work?</h3>
                <p className="text-gray-700">
                  Our AI analyzes your running data to provide personalized insights, training recommendations, and performance analysis. The AI uses advanced language models to understand your running patterns and provide actionable feedback.
                </p>
              </div>

              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">Is my data secure?</h3>
                <p className="text-gray-700">
                  Yes! Your health data is stored locally on your device. We use industry-standard encryption for any data transmitted to our AI services. We do not sell or share your personal data with third parties.
                </p>
              </div>

              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">What Apple Watch models are supported?</h3>
                <p className="text-gray-700">
                  Insight Run works with all Apple Watch models that support HealthKit and workout tracking. For the best experience, we recommend Apple Watch Series 4 or newer.
                </p>
              </div>

              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">How can I delete my data?</h3>
                <p className="text-gray-700">
                  You can delete your data at any time directly from the app's settings. Since most data is stored locally on your device, deleting the app will also remove all local data. For information about data deletion requests, see our <a href="/privacy" className="text-blue-600 hover:text-blue-800 underline">Privacy Policy</a>.
                </p>
              </div>
            </div>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Technical Issues</h2>

            <div className="space-y-6">
              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">The app won't connect to HealthKit</h3>
                <p className="text-gray-700">
                  Make sure you've granted the necessary permissions in your iPhone Settings:
                </p>
                <ol className="list-decimal list-inside ml-4 text-gray-700 space-y-1">
                  <li>Open Settings on your iPhone</li>
                  <li>Scroll down and tap on Insight Run</li>
                  <li>Tap on Health</li>
                  <li>Enable all requested permissions</li>
                </ol>
              </div>

              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">Insights are not generating</h3>
                <p className="text-gray-700">
                  Ensure you have an active internet connection, as AI insights require connectivity to process your data. If the issue persists, try closing and reopening the app.
                </p>
              </div>

              <div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">App crashes or freezes</h3>
                <p className="text-gray-700">
                  Try the following steps:
                </p>
                <ol className="list-decimal list-inside ml-4 text-gray-700 space-y-1">
                  <li>Force close the app and reopen it</li>
                  <li>Restart your iPhone</li>
                  <li>Check for app updates in the App Store</li>
                  <li>If the issue persists, contact support</li>
                </ol>
              </div>
            </div>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Contact Us</h2>
            <p className="text-gray-700 mb-4">
              Can't find what you're looking for? We'd love to hear from you!
            </p>

            <div className="bg-blue-50 border border-blue-200 rounded-lg p-6">
              <h3 className="text-lg font-semibold text-gray-900 mb-3">Email Support</h3>
              <p className="text-gray-700 mb-2">
                For technical support, feature requests, or general inquiries:
              </p>
              <a
                href="mailto:support@insightrun.app"
                className="text-blue-600 hover:text-blue-800 font-semibold underline"
              >
                support@insightrun.app
              </a>

              <p className="text-gray-600 text-sm mt-4">
                We typically respond within 24-48 hours during business days.
              </p>
            </div>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">System Requirements</h2>
            <ul className="list-disc list-inside text-gray-700 space-y-2">
              <li>iOS 15.0 or later</li>
              <li>iPhone 8 or newer</li>
              <li>Apple Watch (optional, for enhanced tracking)</li>
              <li>Active internet connection for AI insights</li>
              <li>HealthKit access permissions</li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">App Updates</h2>
            <p className="text-gray-700">
              We regularly update Insight Run with new features, improvements, and bug fixes. Enable automatic updates in the App Store or check regularly for new versions.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">Feedback</h2>
            <p className="text-gray-700 mb-4">
              Your feedback helps us improve! If you have suggestions for new features or improvements, please email us at{' '}
              <a
                href="mailto:feedback@insightrun.app"
                className="text-blue-600 hover:text-blue-800 underline"
              >
                feedback@insightrun.app
              </a>
            </p>
            <p className="text-gray-700">
              Enjoying Insight Run? Please consider leaving a review on the App Store – it helps other runners discover our app!
            </p>
          </section>

          <section className="mt-12 pt-8 border-t border-gray-200">
            <p className="text-gray-600 text-sm">
              Last updated: October 30, 2025
            </p>
          </section>
        </div>
      </div>
    </div>
  )
}
