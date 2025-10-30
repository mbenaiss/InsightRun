import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Terms of Service - Insight Run',
  description: 'Terms of Service for Insight Run - AI-powered running coach',
}

export default function TermsPage() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-blue-50 to-white">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <h1 className="text-4xl font-bold text-gray-900 mb-8">Terms of Service</h1>

        <div className="prose prose-blue max-w-none">
          <p className="text-gray-700 mb-6">
            <strong>Last Updated:</strong> October 30, 2025
          </p>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">1. Acceptance of Terms</h2>
            <p className="text-gray-700 mb-4">
              Welcome to Insight Run! These Terms of Service ("Terms") govern your access to and use
              of the Insight Run mobile application ("App"), services, and website (collectively,
              the "Service"). By downloading, installing, or using the App, you agree to be bound by
              these Terms.
            </p>
            <p className="text-gray-700">
              If you do not agree to these Terms, please do not use the Service.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">2. Description of Service</h2>
            <p className="text-gray-700 mb-4">
              Insight Run is an AI-powered running coach that provides:
            </p>
            <ul className="list-disc list-inside text-gray-700 space-y-2 mb-4">
              <li>Personalized running insights and analysis</li>
              <li>Workout tracking and performance metrics</li>
              <li>AI-generated training recommendations</li>
              <li>Integration with Apple HealthKit</li>
              <li>Progress tracking and visualization</li>
            </ul>
            <p className="text-gray-700">
              The Service is designed to complement, not replace, professional medical advice or
              coaching services.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">3. Eligibility</h2>
            <p className="text-gray-700 mb-4">
              You must be at least 13 years old to use the Service. If you are under 18, you must
              have your parent or legal guardian's permission to use the Service.
            </p>
            <p className="text-gray-700">
              By using the Service, you represent and warrant that you meet these eligibility
              requirements.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">4. Account and Data</h2>
            <p className="text-gray-700 mb-4">
              <strong>4.1 HealthKit Access:</strong> The App requires access to your Apple HealthKit
              data to function properly. You control which data the App can access through your
              device settings.
            </p>
            <p className="text-gray-700 mb-4">
              <strong>4.2 Data Accuracy:</strong> While we strive for accuracy, you acknowledge that
              the App's insights and recommendations are based on the data provided and may not
              always be accurate or complete.
            </p>
            <p className="text-gray-700">
              <strong>4.3 Your Responsibility:</strong> You are responsible for ensuring the
              accuracy of any data you provide and for maintaining the security of your device.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">5. Acceptable Use</h2>
            <p className="text-gray-700 mb-4">
              You agree to use the Service only for lawful purposes and in accordance with these
              Terms. You agree NOT to:
            </p>
            <ul className="list-disc list-inside text-gray-700 space-y-2">
              <li>Use the Service in any way that violates any applicable law or regulation</li>
              <li>Attempt to reverse engineer, decompile, or disassemble the App</li>
              <li>Use automated systems to access the Service</li>
              <li>Interfere with or disrupt the Service or servers</li>
              <li>Attempt to gain unauthorized access to any portion of the Service</li>
              <li>Use the Service to transmit any viruses, malware, or harmful code</li>
              <li>Impersonate any person or entity or misrepresent your affiliation</li>
            </ul>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">6. Medical Disclaimer</h2>
            <p className="text-gray-700 mb-4">
              <strong>IMPORTANT:</strong> The Service is not a substitute for professional medical
              advice, diagnosis, or treatment.
            </p>
            <p className="text-gray-700 mb-4">
              The insights and recommendations provided by Insight Run are for informational and
              educational purposes only. Always consult with a qualified healthcare provider before
              starting any new exercise program or if you have any concerns about your health.
            </p>
            <p className="text-gray-700">
              The Service is not intended to diagnose, treat, cure, or prevent any disease or
              medical condition. In case of emergency, call your doctor or emergency services
              immediately.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">
              7. Intellectual Property Rights
            </h2>
            <p className="text-gray-700 mb-4">
              <strong>7.1 Our Content:</strong> The Service, including its original content,
              features, and functionality, is owned by Insight Run and is protected by international
              copyright, trademark, patent, trade secret, and other intellectual property laws.
            </p>
            <p className="text-gray-700 mb-4">
              <strong>7.2 Your Data:</strong> You retain all rights to your workout data and
              personal information. By using the Service, you grant us a limited license to process
              your data solely to provide the Service.
            </p>
            <p className="text-gray-700">
              <strong>7.3 Trademarks:</strong> Insight Run and related logos are trademarks of
              Insight Run. You may not use these trademarks without our prior written consent.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">8. Third-Party Services</h2>
            <p className="text-gray-700 mb-4">
              The Service may integrate with or contain links to third-party services, including:
            </p>
            <ul className="list-disc list-inside text-gray-700 space-y-2 mb-4">
              <li>Apple HealthKit</li>
              <li>AI processing services (OpenRouter)</li>
              <li>Analytics services</li>
            </ul>
            <p className="text-gray-700">
              We are not responsible for the content, privacy policies, or practices of third-party
              services. Your use of third-party services is at your own risk.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">9. Privacy</h2>
            <p className="text-gray-700">
              Your privacy is important to us. Please review our{' '}
              <a href="/privacy" className="text-blue-600 hover:text-blue-800 underline">
                Privacy Policy
              </a>{' '}
              to understand how we collect, use, and protect your information.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">10. Fees and Payments</h2>
            <p className="text-gray-700 mb-4">
              <strong>10.1 Free Features:</strong> Certain features of the Service are currently
              provided free of charge.
            </p>
            <p className="text-gray-700 mb-4">
              <strong>10.2 Premium Features:</strong> We may offer premium features or subscriptions
              in the future. Any fees will be clearly disclosed before you make a purchase.
            </p>
            <p className="text-gray-700">
              <strong>10.3 In-App Purchases:</strong> All purchases are processed through the Apple
              App Store and are subject to Apple's terms and conditions.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">
              11. Disclaimer of Warranties
            </h2>
            <p className="text-gray-700 mb-4">
              THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND,
              EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO:
            </p>
            <ul className="list-disc list-inside text-gray-700 space-y-2 mb-4">
              <li>
                Warranties of merchantability, fitness for a particular purpose, or non-infringement
              </li>
              <li>Warranties that the Service will be uninterrupted, secure, or error-free</li>
              <li>
                Warranties regarding the accuracy, reliability, or completeness of the Service
              </li>
            </ul>
            <p className="text-gray-700">
              Your use of the Service is at your sole risk. No advice or information obtained from
              us shall create any warranty not expressly stated in these Terms.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">
              12. Limitation of Liability
            </h2>
            <p className="text-gray-700 mb-4">
              TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL INSIGHT RUN, ITS
              OFFICERS, DIRECTORS, EMPLOYEES, OR AGENTS BE LIABLE FOR ANY INDIRECT, INCIDENTAL,
              SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO:
            </p>
            <ul className="list-disc list-inside text-gray-700 space-y-2 mb-4">
              <li>Loss of profits, data, use, or goodwill</li>
              <li>Personal injury or property damage</li>
              <li>Service interruptions</li>
              <li>Any other damages arising out of or related to your use of the Service</li>
            </ul>
            <p className="text-gray-700">
              This limitation applies whether the alleged liability is based on contract, tort,
              negligence, strict liability, or any other basis, even if we have been advised of the
              possibility of such damage.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">13. Indemnification</h2>
            <p className="text-gray-700">
              You agree to defend, indemnify, and hold harmless Insight Run and its licensees,
              affiliates, and their respective officers, directors, employees, and agents from and
              against any claims, liabilities, damages, judgments, awards, losses, costs, expenses,
              or fees (including reasonable attorneys' fees) arising out of or relating to your
              violation of these Terms or your use of the Service.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">
              14. Modifications to Service
            </h2>
            <p className="text-gray-700 mb-4">
              We reserve the right to modify, suspend, or discontinue the Service (or any part
              thereof) at any time, with or without notice, for any reason.
            </p>
            <p className="text-gray-700">
              We shall not be liable to you or any third party for any modification, suspension, or
              discontinuance of the Service.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">15. Changes to Terms</h2>
            <p className="text-gray-700 mb-4">
              We may update these Terms from time to time. We will notify you of any changes by:
            </p>
            <ul className="list-disc list-inside text-gray-700 space-y-2 mb-4">
              <li>Posting the new Terms within the App</li>
              <li>Updating the "Last Updated" date at the top of these Terms</li>
              <li>Sending you a notification through the App or email (for material changes)</li>
            </ul>
            <p className="text-gray-700">
              Your continued use of the Service after any changes constitutes your acceptance of the
              new Terms.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">16. Termination</h2>
            <p className="text-gray-700 mb-4">
              <strong>16.1 By You:</strong> You may stop using the Service at any time by deleting
              the App from your device.
            </p>
            <p className="text-gray-700 mb-4">
              <strong>16.2 By Us:</strong> We may terminate or suspend your access to the Service
              immediately, without prior notice or liability, if you breach these Terms.
            </p>
            <p className="text-gray-700">
              <strong>16.3 Effect of Termination:</strong> Upon termination, your right to use the
              Service will immediately cease. Sections of these Terms that by their nature should
              survive termination shall survive.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">17. Governing Law</h2>
            <p className="text-gray-700">
              These Terms shall be governed by and construed in accordance with the laws of the
              jurisdiction in which Insight Run operates, without regard to its conflict of law
              provisions. Any disputes arising under these Terms shall be resolved in the
              appropriate courts of that jurisdiction.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">18. Severability</h2>
            <p className="text-gray-700">
              If any provision of these Terms is held to be invalid or unenforceable, the remaining
              provisions shall continue to be valid and enforceable to the fullest extent permitted
              by law.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">19. Entire Agreement</h2>
            <p className="text-gray-700">
              These Terms, together with our Privacy Policy, constitute the entire agreement between
              you and Insight Run regarding the Service and supersede all prior agreements and
              understandings.
            </p>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">20. Contact Information</h2>
            <p className="text-gray-700 mb-4">
              If you have any questions about these Terms, please contact us:
            </p>
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-6">
              <p className="text-gray-700 mb-2">
                <strong>Email:</strong>{' '}
                <a
                  href="mailto:support@altcode.studio"
                  className="text-blue-600 hover:text-blue-800 underline"
                >
                  support@altcode.studio
                </a>
              </p>
              <p className="text-gray-700">
                <strong>Support:</strong>{' '}
                <a href="/support" className="text-blue-600 hover:text-blue-800 underline">
                  Visit our Support page
                </a>
              </p>
            </div>
          </section>

          <section className="mb-8">
            <h2 className="text-2xl font-semibold text-gray-900 mb-4">21. Apple-Specific Terms</h2>
            <p className="text-gray-700 mb-4">
              The following additional terms apply to your use of the App on iOS devices:
            </p>
            <ul className="list-disc list-inside text-gray-700 space-y-2">
              <li>These Terms are between you and Insight Run, not Apple Inc.</li>
              <li>Apple has no obligation to provide any maintenance or support services</li>
              <li>Apple is not responsible for addressing any claims relating to the App</li>
              <li>Apple and its subsidiaries are third-party beneficiaries of these Terms</li>
              <li>You must comply with applicable third-party terms when using the App</li>
            </ul>
          </section>

          <section className="mt-12 pt-8 border-t border-gray-200">
            <p className="text-gray-600 text-sm mb-4">
              By using Insight Run, you acknowledge that you have read, understood, and agree to be
              bound by these Terms of Service.
            </p>
            <p className="text-gray-600 text-sm">
              <strong>Last updated:</strong> October 30, 2025
            </p>
          </section>
        </div>
      </div>
    </div>
  )
}
