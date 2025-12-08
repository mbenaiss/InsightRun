'use client'

import { useEffect, useState } from 'react'
import { adminAPI } from '@/lib/api'

export default function FeaturesPage() {
  const [features, setFeatures] = useState<Record<string, boolean>>({})
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  // New feature form
  const [showAddForm, setShowAddForm] = useState(false)
  const [newFeatureKey, setNewFeatureKey] = useState('')
  const [newFeatureEnabled, setNewFeatureEnabled] = useState(false)

  useEffect(() => {
    loadFeatures()
  }, [])

  const loadFeatures = async () => {
    try {
      const config = await adminAPI.getConfig()
      setFeatures(config.features)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load features')
    } finally {
      setLoading(false)
    }
  }

  const toggleFeature = async (key: string) => {
    const newValue = !features[key]
    const previousFeatures = { ...features }

    // Optimistic update
    setFeatures({ ...features, [key]: newValue })
    setError('')
    setSuccess('')
    setSaving(true)

    try {
      await adminAPI.updateFeatures({ [key]: newValue })
      setSuccess(`${key} ${newValue ? 'enabled' : 'disabled'}`)
      setTimeout(() => setSuccess(''), 3000)
    } catch (e) {
      setFeatures(previousFeatures)
      setError(e instanceof Error ? e.message : 'Failed to update feature')
    } finally {
      setSaving(false)
    }
  }

  const addFeature = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!newFeatureKey.trim()) {
      setError('Feature key is required')
      return
    }

    // Validate key format (snake_case)
    const keyRegex = /^[a-z][a-z0-9_]*$/
    if (!keyRegex.test(newFeatureKey)) {
      setError('Feature key must be in snake_case format (e.g., my_feature_enabled)')
      return
    }

    if (features[newFeatureKey] !== undefined) {
      setError('Feature already exists')
      return
    }

    setSaving(true)
    setError('')

    try {
      await adminAPI.updateFeatures({ [newFeatureKey]: newFeatureEnabled })
      setFeatures({ ...features, [newFeatureKey]: newFeatureEnabled })
      setSuccess(`Feature "${newFeatureKey}" added`)
      setNewFeatureKey('')
      setNewFeatureEnabled(false)
      setShowAddForm(false)
      setTimeout(() => setSuccess(''), 3000)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to add feature')
    } finally {
      setSaving(false)
    }
  }

  const deleteFeature = async (key: string) => {
    if (!confirm(`Delete feature "${key}"? This cannot be undone.`)) {
      return
    }

    const previousFeatures = { ...features }
    const newFeatures = { ...features }
    delete newFeatures[key]
    setFeatures(newFeatures)

    setSaving(true)
    setError('')

    try {
      // Send the full feature set without the deleted key
      await adminAPI.setAllFeatures(newFeatures)
      setSuccess(`Feature "${key}" deleted`)
      setTimeout(() => setSuccess(''), 3000)
    } catch (e) {
      setFeatures(previousFeatures)
      setError(e instanceof Error ? e.message : 'Failed to delete feature')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
      </div>
    )
  }

  return (
    <div className="space-y-8">
      {/* Hero Header */}
      <div className="relative bg-gradient-to-r from-emerald-900 to-teal-900 rounded-2xl p-8 text-white shadow-lg overflow-hidden">
        <div className="absolute top-0 right-0 p-4 opacity-10">
          <svg className="w-64 h-64 transform rotate-6" fill="currentColor" viewBox="0 0 24 24">
            <path
              d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </div>
        <div className="relative z-10 flex flex-col md:flex-row md:items-end justify-between gap-6">
          <div>
            <h2 className="text-3xl font-bold mb-2">Feature Flags</h2>
            <p className="text-emerald-100 max-w-xl leading-relaxed">
              Manage system capabilities and roll out new features safely. Toggle functionality on
              or off instantly across all clients.
            </p>
          </div>
          <div className="flex gap-3">
            <button
              onClick={loadFeatures}
              className="px-4 py-2.5 bg-white/10 backdrop-blur-sm text-white rounded-xl hover:bg-white/20 transition-all font-medium flex items-center gap-2"
            >
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
              Refresh
            </button>
            <button
              onClick={() => setShowAddForm(!showAddForm)}
              className="px-5 py-2.5 bg-white text-emerald-900 rounded-xl hover:bg-emerald-50 transition-all shadow-lg shadow-black/10 font-bold flex items-center gap-2"
            >
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={3}
                  d="M12 4v16m8-8H4"
                />
              </svg>
              Add Feature
            </button>
          </div>
        </div>
      </div>

      {error && (
        <div className="bg-red-50 text-red-600 p-4 rounded-xl border border-red-100 flex items-center gap-3">
          <span className="text-xl">⚠️</span>
          {error}
        </div>
      )}
      {success && (
        <div className="bg-green-50 text-green-600 p-4 rounded-xl border border-green-100 flex items-center gap-3">
          <span className="text-xl">✓</span>
          {success}
        </div>
      )}

      {/* Add Feature Form */}
      {showAddForm && (
        <div className="bg-white rounded-xl shadow-lg border border-emerald-100 p-6 relative overflow-hidden animate-in fade-in slide-in-from-top-4 duration-200">
          <div className="absolute top-0 left-0 w-1 h-full bg-emerald-500"></div>
          <div className="flex items-center justify-between mb-6">
            <h3 className="text-lg font-bold text-gray-900 flex items-center gap-2">
              <span className="p-1.5 bg-emerald-100 text-emerald-600 rounded-lg">
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M12 9v3m0 0v3m0-3h3m-3 0H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
              </span>
              Add New Feature
            </h3>
            <button
              onClick={() => setShowAddForm(false)}
              className="text-gray-400 hover:text-gray-600"
            >
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>

          <form onSubmit={addFeature} className="grid grid-cols-1 md:grid-cols-12 gap-6">
            <div className="md:col-span-5">
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                Feature Key
              </label>
              <div className="relative">
                <input
                  type="text"
                  value={newFeatureKey}
                  onChange={(e) =>
                    setNewFeatureKey(e.target.value.toLowerCase().replace(/\s+/g, '_'))
                  }
                  placeholder="e.g. advanced_analytics_enabled"
                  className="w-full px-4 py-2.5 border border-gray-200 rounded-xl focus:ring-2 focus:ring-emerald-500 focus:border-transparent font-mono text-sm transition-all"
                />
              </div>
              <p className="text-xs text-gray-500 mt-1.5 flex items-center gap-1">
                <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                Snake case only (lower_case_with_underscores)
              </p>
            </div>

            <div className="md:col-span-4 flex flex-col justify-center">
              <label className="block text-sm font-semibold text-gray-700 mb-3">
                Initial State
              </label>
              <div className="flex items-center gap-3">
                <button
                  type="button"
                  onClick={() => setNewFeatureEnabled(!newFeatureEnabled)}
                  className={`relative inline-flex h-7 w-12 items-center rounded-full transition-all focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 ${
                    newFeatureEnabled ? 'bg-emerald-500' : 'bg-gray-200'
                  }`}
                >
                  <span
                    className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform duration-200 ease-in-out ${
                      newFeatureEnabled ? 'translate-x-6' : 'translate-x-1'
                    }`}
                  />
                </button>
                <span
                  className={`text-sm font-medium px-2 py-1 rounded ${newFeatureEnabled ? 'bg-emerald-50 text-emerald-700' : 'bg-gray-100 text-gray-600'}`}
                >
                  {newFeatureEnabled ? 'Enabled' : 'Disabled'}
                </span>
              </div>
            </div>

            <div className="md:col-span-3 flex items-end gap-3">
              <button
                type="submit"
                disabled={saving}
                className="w-full px-4 py-2.5 bg-emerald-600 text-white rounded-xl hover:bg-emerald-700 transition-all shadow-sm hover:shadow disabled:opacity-50 font-medium"
              >
                {saving ? 'Adding...' : 'Add Feature'}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Features List */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-100 bg-gray-50/50 flex items-center justify-between">
          <h3 className="font-bold text-gray-900">Configuration Keys</h3>
          <span className="text-xs font-medium text-gray-500 bg-gray-200/50 px-2 py-1 rounded-full">
            {Object.keys(features).length} keys
          </span>
        </div>
        <div className="divide-y divide-gray-100">
          {Object.keys(features).length === 0 ? (
            <div className="p-12 text-center text-gray-500 flex flex-col items-center">
              <div className="w-16 h-16 bg-gray-50 rounded-full flex items-center justify-center mb-4 text-3xl opacity-50">
                ⚙️
              </div>
              <p className="text-lg font-medium text-gray-900">No features configured</p>
              <p className="text-sm mt-1">Click "Add Feature" to create your first flag.</p>
            </div>
          ) : (
            Object.entries(features).map(([key, value]) => (
              <div
                key={key}
                className="p-5 flex items-center justify-between hover:bg-gray-50/50 transition-colors group"
              >
                <div className="flex items-center gap-4">
                  <div
                    className={`w-2 h-2 rounded-full ${value ? 'bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.6)]' : 'bg-gray-300'}`}
                  ></div>
                  <div>
                    <h3 className="text-sm font-bold text-gray-900 font-mono tracking-tight">
                      {key}
                    </h3>
                    <p className="text-xs text-gray-500 mt-0.5">
                      {value ? 'Active' : 'Inactive'} feature flag
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-6">
                  <div className="flex items-center gap-3">
                    <span
                      className={`text-xs font-medium transition-colors ${value ? 'text-emerald-600' : 'text-gray-400'}`}
                    >
                      {value ? 'ON' : 'OFF'}
                    </span>
                    <button
                      onClick={() => toggleFeature(key)}
                      disabled={saving}
                      className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 ${
                        value ? 'bg-emerald-600' : 'bg-gray-200'
                      } ${saving ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}
                    >
                      <span
                        className={`inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform duration-200 ease-in-out ${
                          value ? 'translate-x-6' : 'translate-x-1'
                        }`}
                      />
                    </button>
                  </div>
                  <div className="w-px h-8 bg-gray-100 mx-2"></div>
                  <button
                    onClick={() => deleteFeature(key)}
                    disabled={saving}
                    className="p-2 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-all disabled:opacity-50 opacity-0 group-hover:opacity-100"
                    title="Delete feature"
                  >
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                      />
                    </svg>
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      {/* Info Box */}
      <div className="bg-blue-50/50 border border-blue-100 rounded-xl p-5 flex gap-4">
        <div className="flex-shrink-0 w-10 h-10 bg-blue-100 text-blue-600 rounded-lg flex items-center justify-center">
          <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
        </div>
        <div>
          <h4 className="font-semibold text-blue-900">Synchronization Info</h4>
          <p className="text-sm text-blue-700 mt-1 leading-relaxed">
            Changes take effect immediately on the server. Client applications (iOS/Web) update
            their configuration within 5 minutes of their next foreground activity or restart. The
            system uses snake_case for keys to maintain compatibility.
          </p>
        </div>
      </div>
    </div>
  )
}
