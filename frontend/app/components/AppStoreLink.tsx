'use client'

import type { ReactNode } from 'react'
import { track } from '../lib/analytics'
import { APP_STORE_URL } from '../lib/constants'

type Props = {
  location: 'header' | 'hero' | 'cta' | 'footer'
  className?: string
  children: ReactNode
}

export default function AppStoreLink({ location, className, children }: Props) {
  return (
    <a
      href={APP_STORE_URL}
      target="_blank"
      rel="noopener noreferrer"
      className={className}
      onClick={() => track('app_store_clicked', { location })}
    >
      {children}
    </a>
  )
}
