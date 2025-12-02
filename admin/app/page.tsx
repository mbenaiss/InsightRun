'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { adminAPI } from '@/lib/api'

export default function LoginPage() {
  const [secret, setSecret] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const router = useRouter()

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      adminAPI.setAdminSecret(secret)
      // Test the connection by fetching config
      await adminAPI.getConfig()
      // Store in sessionStorage for the session
      sessionStorage.setItem('adminSecret', secret)
      router.push('/dashboard')
    } catch {
      setError('Invalid admin credentials')
      adminAPI.setAdminSecret('')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-900 via-blue-950 to-slate-900">
      <div className="absolute inset-0 bg-[radial-gradient(#ffffff33_1px,transparent_1px)] [background-size:16px_16px] [mask-image:radial-gradient(ellipse_at_center,black_50%,transparent_100%)]"></div>
      <div className="max-w-md w-full mx-4 relative z-10">
        <div className="bg-white/10 backdrop-blur-xl border border-white/20 rounded-2xl shadow-2xl p-8">
          <div className="text-center mb-8">
            <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-blue-600 mb-4 shadow-lg shadow-blue-600/30">
              <span className="text-3xl">⚡</span>
            </div>
            <h1 className="text-3xl font-bold text-white">InsightRun Admin</h1>
            <p className="text-blue-200 mt-2">Enter your admin secret to continue</p>
          </div>

          <form onSubmit={handleLogin} className="space-y-6">
            <div>
              <label htmlFor="secret" className="block text-sm font-medium text-blue-100 mb-2">
                Admin Secret
              </label>
              <input
                id="secret"
                type="password"
                value={secret}
                onChange={(e) => setSecret(e.target.value)}
                className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl text-white placeholder-white/40 focus:ring-2 focus:ring-blue-500 focus:border-transparent transition outline-none"
                placeholder="Enter admin secret..."
                required
              />
            </div>

            {error && (
              <div className="bg-red-500/10 border border-red-500/20 text-red-200 px-4 py-3 rounded-xl text-sm flex items-center gap-2">
                <span className="text-lg">⚠️</span>
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full bg-gradient-to-r from-blue-600 to-blue-500 text-white py-3 rounded-xl font-medium shadow-lg shadow-blue-600/20 hover:shadow-blue-600/40 hover:from-blue-500 hover:to-blue-400 transition-all disabled:opacity-50 disabled:cursor-not-allowed transform hover:-translate-y-0.5 active:translate-y-0"
            >
              {loading ? (
                <span className="flex items-center justify-center gap-2">
                  <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  Verifying...
                </span>
              ) : (
                'Login'
              )}
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}
