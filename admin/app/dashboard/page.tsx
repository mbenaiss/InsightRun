'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { type AdminConfig, adminAPI } from '@/lib/api'

export default function DashboardOverview() {
  const [config, setConfig] = useState<AdminConfig | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    loadConfig()
  }, [])

  const loadConfig = async () => {
    try {
      const data = await adminAPI.getConfig()
      setConfig(data)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load config')
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="flex justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
      </div>
    )
  }

  if (error) {
    return (
      <div className="bg-red-50 text-red-600 p-4 rounded-lg">
        {error}
        <button onClick={loadConfig} className="ml-4 underline">
          Retry
        </button>
      </div>
    )
  }

  const features = config?.features || {}
  const enabledCount = Object.values(features).filter(Boolean).length
  const totalCount = Object.keys(features).length

  return (
    <div className="space-y-8">
      {/* Hero / Welcome Section */}
      <div className="relative bg-gradient-to-r from-slate-900 to-slate-800 rounded-2xl p-8 text-white shadow-lg overflow-hidden">
        <div className="absolute top-0 right-0 p-4 opacity-10">
          <svg className="w-64 h-64 transform rotate-12" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
          </svg>
        </div>
        <div className="relative z-10">
          <h2 className="text-3xl font-bold mb-2">System Overview</h2>
          <p className="text-slate-300 max-w-xl">
            Welcome back to the InsightRun command center. Monitor system health, manage feature flags, and configure AI models from this central dashboard.
          </p>
          <div className="mt-6 flex items-center gap-4">
            <div className="flex items-center gap-2 px-3 py-1 bg-emerald-500/20 border border-emerald-500/30 rounded-full text-sm text-emerald-200">
              <span className="w-2 h-2 bg-emerald-400 rounded-full animate-pulse"></span>
              All Systems Operational
            </div>
            <span className="text-xs text-slate-400">Last synced: Just now</span>
          </div>
        </div>
      </div>

      {/* Key Metrics Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Feature Flags Metric */}
        <div className="bg-white rounded-xl p-6 border border-gray-100 shadow-sm hover:shadow-md transition-all duration-200 group">
          <div className="flex justify-between items-start mb-4">
            <div>
              <p className="text-sm font-medium text-gray-500">Active Features</p>
              <h3 className="text-3xl font-bold text-gray-900 mt-1">
                {enabledCount}
                <span className="text-lg text-gray-400 font-normal ml-1">/ {totalCount}</span>
              </h3>
            </div>
            <div className="p-2 bg-blue-50 rounded-lg text-blue-600 group-hover:bg-blue-100 transition-colors">
              <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
          </div>
          <div className="w-full bg-gray-100 rounded-full h-1.5 mb-2">
            <div 
              className="bg-blue-500 h-1.5 rounded-full transition-all duration-500" 
              style={{ width: `${(enabledCount / totalCount) * 100}%` }}
            ></div>
          </div>
          <p className="text-xs text-gray-500">
            {((enabledCount / totalCount) * 100).toFixed(0)}% utilization
          </p>
        </div>

        {/* Rate Limits Metric */}
        <div className="bg-white rounded-xl p-6 border border-gray-100 shadow-sm hover:shadow-md transition-all duration-200 group">
          <div className="flex justify-between items-start mb-4">
            <div>
              <p className="text-sm font-medium text-gray-500">IP Rate Limit</p>
              <h3 className="text-3xl font-bold text-gray-900 mt-1">
                {config?.rate_limits?.current?.ipLimit || 100}
              </h3>
            </div>
            <div className="p-2 bg-amber-50 rounded-lg text-amber-600 group-hover:bg-amber-100 transition-colors">
              <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
            </div>
          </div>
          <div className="flex items-center text-sm text-amber-700 bg-amber-50 px-2 py-1 rounded-md w-fit">
            <span className="font-medium">Standard Tier</span>
          </div>
          <p className="text-xs text-gray-500 mt-3">Requests per hour per IP</p>
        </div>

        {/* User Limit Metric */}
        <div className="bg-white rounded-xl p-6 border border-gray-100 shadow-sm hover:shadow-md transition-all duration-200 group">
          <div className="flex justify-between items-start mb-4">
            <div>
              <p className="text-sm font-medium text-gray-500">Monthly Cap</p>
              <h3 className="text-3xl font-bold text-gray-900 mt-1">
                {config?.rate_limits?.current?.userLimit || 1000}
              </h3>
            </div>
            <div className="p-2 bg-purple-50 rounded-lg text-purple-600 group-hover:bg-purple-100 transition-colors">
              <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
              </svg>
            </div>
          </div>
          <div className="flex items-center text-sm text-purple-700 bg-purple-50 px-2 py-1 rounded-md w-fit">
            <span className="font-medium">User Allocation</span>
          </div>
          <p className="text-xs text-gray-500 mt-3">Requests per user / month</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Feature Status List */}
        <div className="lg:col-span-2 bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
          <div className="px-6 py-4 border-b border-gray-100 flex justify-between items-center bg-gray-50/30">
            <h3 className="font-semibold text-gray-900">System Modules</h3>
            <Link href="/dashboard/features" className="text-sm text-blue-600 hover:text-blue-700 font-medium">
              Manage All &rarr;
            </Link>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-px bg-gray-100">
            {Object.entries(features).map(([key, value]) => (
              <div key={key} className="bg-white p-4 flex items-center justify-between group hover:bg-gray-50 transition-colors">
                <div className="flex items-center gap-3">
                  <div className={`w-2 h-2 rounded-full ${value ? 'bg-emerald-500' : 'bg-gray-300'}`}></div>
                  <span className="text-sm font-medium text-gray-700 group-hover:text-gray-900">
                    {key.replace(/_/g, ' ').replace('enabled', '')}
                  </span>
                </div>
                <span className={`text-xs font-medium px-2 py-1 rounded-full ${
                  value ? 'bg-emerald-50 text-emerald-700' : 'bg-gray-100 text-gray-500'
                }`}>
                  {value ? 'Active' : 'Inactive'}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Quick Actions Column */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden flex flex-col">
          <div className="px-6 py-4 border-b border-gray-100 bg-gray-50/30">
            <h3 className="font-semibold text-gray-900">Quick Actions</h3>
          </div>
          <div className="p-4 space-y-3 flex-1">
            <Link
              href="/dashboard/features"
              className="flex items-start gap-4 p-3 rounded-xl hover:bg-gray-50 transition-colors group"
            >
              <div className="mt-1 p-2 bg-blue-50 text-blue-600 rounded-lg group-hover:bg-blue-100 transition-colors">
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4" />
                </svg>
              </div>
              <div>
                <h4 className="font-medium text-gray-900">Features</h4>
                <p className="text-xs text-gray-500 mt-0.5">Manage system capabilities</p>
              </div>
            </Link>

            <Link
              href="/dashboard/models"
              className="flex items-start gap-4 p-3 rounded-xl hover:bg-gray-50 transition-colors group"
            >
              <div className="mt-1 p-2 bg-purple-50 text-purple-600 rounded-lg group-hover:bg-purple-100 transition-colors">
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19.428 15.428a2 2 0 00-1.022-.547l-2.384-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z" />
                </svg>
              </div>
              <div>
                <h4 className="font-medium text-gray-900">AI Models</h4>
                <p className="text-xs text-gray-500 mt-0.5">Configure model mapping</p>
              </div>
            </Link>

            <Link
              href="/dashboard/blocked"
              className="flex items-start gap-4 p-3 rounded-xl hover:bg-gray-50 transition-colors group"
            >
              <div className="mt-1 p-2 bg-red-50 text-red-600 rounded-lg group-hover:bg-red-100 transition-colors">
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                </svg>
              </div>
              <div>
                <h4 className="font-medium text-gray-900">Blocked Users</h4>
                <p className="text-xs text-gray-500 mt-0.5">Manage restrictions</p>
              </div>
            </Link>
          </div>
          <div className="p-4 bg-gray-50 border-t border-gray-100">
            <div className="flex items-center gap-2 text-xs text-gray-500">
              <div className="w-2 h-2 bg-green-500 rounded-full"></div>
              API Status: Online
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
