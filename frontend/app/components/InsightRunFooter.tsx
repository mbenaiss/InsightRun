import Image from 'next/image'
import Link from 'next/link'
import { SUPPORT_EMAIL } from '../lib/constants'
import AppStoreLink from './AppStoreLink'

const links = [
  { href: '/support', label: 'Help center' },
  { href: `mailto:${SUPPORT_EMAIL}`, label: 'Contact', external: true },
  { href: '/privacy', label: 'Privacy policy' },
  { href: '/terms', label: 'Terms of service' },
]

export default function InsightRunFooter() {
  return (
    <footer className="border-t border-line py-12">
      <div className="mx-auto flex max-w-6xl flex-col gap-8 px-6 md:flex-row md:items-center md:justify-between">
        <div className="flex items-center gap-3">
          <Image
            src="/app-icon.webp"
            unoptimized
            alt=""
            width={28}
            height={28}
            className="rounded-[7px]"
          />
          <span className="font-display font-extrabold tracking-[-0.02em] text-foreground">
            Insight Run
          </span>
          <span className="text-sm text-muted-foreground">© {new Date().getFullYear()}</span>
        </div>
        <nav aria-label="Footer">
          <ul className="flex flex-wrap gap-x-7 gap-y-3 text-sm">
            <li>
              <AppStoreLink
                location="footer"
                className="text-muted-foreground transition-colors hover:text-foreground"
              >
                App Store
              </AppStoreLink>
            </li>
            {links.map((l) => (
              <li key={l.label}>
                {l.external ? (
                  <a
                    href={l.href}
                    {...(l.href.startsWith('http')
                      ? { target: '_blank', rel: 'noopener noreferrer' }
                      : {})}
                    className="text-muted-foreground transition-colors hover:text-foreground"
                  >
                    {l.label}
                  </a>
                ) : (
                  <Link
                    href={l.href}
                    className="text-muted-foreground transition-colors hover:text-foreground"
                  >
                    {l.label}
                  </Link>
                )}
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </footer>
  )
}
