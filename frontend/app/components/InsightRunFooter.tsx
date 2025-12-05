import Image from 'next/image'
import Link from 'next/link'

export default function InsightRunFooter() {
  return (
    <footer className="bg-background border-t border-muted pt-20 pb-10">
      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 md:grid-cols-12 gap-12 mb-16">
          {/* Brand Section */}
          <div className="md:col-span-5 space-y-6">
            <Link href="/" className="flex items-center gap-3">
              <Image
                src="/app-icon.png"
                alt="InsightRun logo"
                width={48}
                height={48}
                className="rounded-xl"
              />
              <span className="text-2xl font-bold text-foreground tracking-tight">Insight Run</span>
            </Link>
            <p className="text-muted-foreground leading-relaxed max-w-sm">
              Your personal AI running coach. <br />
              Train smarter, recover better, and achieve your goals with data-driven insights.
            </p>
            <div className="pt-4">
              <a
                href="https://apps.apple.com/us/app/insight-run/id6754607965"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-block hover:opacity-80 transition-opacity"
              >
                <Image
                  src="/app-store-badge.svg"
                  alt="Download on the App Store"
                  width={140}
                  height={48}
                  className="h-12 w-auto"
                />
              </a>
            </div>
          </div>

          {/* Navigation Columns */}
          <div className="md:col-span-7 grid grid-cols-2 sm:grid-cols-3 gap-8">
            <div>
              <h3 className="font-semibold text-foreground mb-6">Product</h3>
              <ul className="space-y-4">
                <li>
                  <a
                    href="#features"
                    className="text-muted-foreground hover:text-primary transition-colors"
                  >
                    Features
                  </a>
                </li>
                <li>
                  <a
                    href="#screenshots"
                    className="text-muted-foreground hover:text-primary transition-colors"
                  >
                    Preview
                  </a>
                </li>
                <li>
                  <a
                    href="https://apps.apple.com/us/app/insight-run/id6754607965"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-muted-foreground hover:text-primary transition-colors"
                  >
                    Download
                  </a>
                </li>
              </ul>
            </div>

            <div>
              <h3 className="font-semibold text-foreground mb-6">Support</h3>
              <ul className="space-y-4">
                <li>
                  <Link
                    href="/support"
                    className="text-muted-foreground hover:text-primary transition-colors"
                  >
                    Help Center
                  </Link>
                </li>
                <li>
                  <a
                    href="mailto:support@altcode.studio"
                    className="text-muted-foreground hover:text-primary transition-colors"
                  >
                    Contact Us
                  </a>
                </li>
              </ul>
            </div>

            <div>
              <h3 className="font-semibold text-foreground mb-6">Legal</h3>
              <ul className="space-y-4">
                <li>
                  <Link
                    href="/privacy"
                    className="text-muted-foreground hover:text-primary transition-colors"
                  >
                    Privacy Policy
                  </Link>
                </li>
                <li>
                  <Link
                    href="/terms"
                    className="text-muted-foreground hover:text-primary transition-colors"
                  >
                    Terms of Service
                  </Link>
                </li>
              </ul>
            </div>
          </div>
        </div>

        {/* Bottom Bar */}
        <div className="pt-8 border-t border-muted flex flex-col md:flex-row justify-between items-center gap-4">
          <p className="text-muted-foreground text-sm">
            © {new Date().getFullYear()} Insight Run. All rights reserved.
          </p>
          <div className="flex gap-6">{/* Social links could go here */}</div>
        </div>
      </div>
    </footer>
  )
}
