'use client'

import Image from 'next/image'
import Link from 'next/link'
import { useEffect, useState } from 'react'
import { APP_STORE_URL } from '../lib/constants'
import { ThemeToggle } from './ThemeToggle'

const links = [
  { href: '/#tour', label: 'Tour' },
  { href: '/#features', label: 'Features' },
  { href: '/#privacy', label: 'Privacy' },
  { href: '/support', label: 'Support' },
]

export default function InsightRunHeader() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 20)
    handleScroll()
    window.addEventListener('scroll', handleScroll, { passive: true })
    return () => window.removeEventListener('scroll', handleScroll)
  }, [])

  return (
    <header
      className={`fixed inset-x-0 top-0 z-50 border-b transition-colors duration-300 ${
        scrolled
          ? 'border-line bg-background/85 backdrop-blur-md'
          : 'border-transparent bg-transparent'
      }`}
    >
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-6 px-6">
        <Link href="/" className="flex items-center gap-3">
          <Image
            src="/app-icon.webp"
            unoptimized
            alt=""
            width={32}
            height={32}
            className="rounded-[8px]"
          />
          <span className="font-display text-lg font-extrabold tracking-[-0.02em] text-foreground">
            Insight Run
          </span>
        </Link>

        <nav aria-label="Main" className="hidden items-center gap-8 md:flex">
          {links.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
            >
              {l.label}
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-3">
          <ThemeToggle />
          <a
            href={APP_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-full bg-primary px-5 py-2 text-sm font-semibold text-on-primary transition-opacity hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            Download
          </a>
        </div>
      </div>
    </header>
  )
}
