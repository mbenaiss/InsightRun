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
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold text-gray-900">Feature Flags</h2>
        <div className="flex gap-3">
          <button
            onClick={() => setShowAddForm(!showAddForm)}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition text-sm font-medium"
          >
            + Add Feature
          </button>
          <button
            onClick={loadFeatures}
            className="text-sm text-blue-600 hover:text-blue-700 transition"
          >
            Refresh
          </button>
        </div>
      </div>

      {error && <div className="bg-red-50 text-red-600 p-4 rounded-lg">{error}</div>}
      {success && <div className="bg-green-50 text-green-600 p-4 rounded-lg">{success}</div>}

      {/* Add Feature Form */}
      {showAddForm && (
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Add New Feature</h3>
          <form onSubmit={addFeature} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Feature Key</label>
              <input
                type="text"
                value={newFeatureKey}
                onChange={(e) =>
                  setNewFeatureKey(e.target.value.toLowerCase().replace(/\s+/g, '_'))
                }
                placeholder="my_feature_enabled"
                className="w-full px-4 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
              <p className="text-xs text-gray-500 mt-1">
                Use snake_case format (e.g., strava_enabled)
              </p>
            </div>
            <div className="flex items-center gap-3">
              <label className="text-sm font-medium text-gray-700">Initial State:</label>
              <button
                type="button"
                onClick={() => setNewFeatureEnabled(!newFeatureEnabled)}
                className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors ${
                  newFeatureEnabled ? 'bg-blue-600' : 'bg-gray-200'
                }`}
              >
                <span
                  className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${
                    newFeatureEnabled ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
              <span className="text-sm text-gray-600">
                {newFeatureEnabled ? 'Enabled' : 'Disabled'}
              </span>
            </div>
            <div className="flex gap-3">
              <button
                type="submit"
                disabled={saving}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition text-sm font-medium disabled:opacity-50"
              >
                {saving ? 'Adding...' : 'Add Feature'}
              </button>
              <button
                type="button"
                onClick={() => {
                  setShowAddForm(false)
                  setNewFeatureKey('')
                  setNewFeatureEnabled(false)
                }}
                className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition text-sm font-medium"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Features List */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 divide-y divide-gray-100">
        {Object.keys(features).length === 0 ? (
          <div className="p-6 text-center text-gray-500">
            No features configured. Click &quot;Add Feature&quot; to create one.
          </div>
        ) : (
          Object.entries(features).map(([key, value]) => (
            <div
              key={key}
              className="p-6 flex items-center justify-between hover:bg-gray-50/50 transition-colors duration-150"
            >
              <div className="flex-1">
                <h3 className="text-base font-semibold text-gray-900 font-mono">{key}</h3>
              </div>
              <div className="flex items-center gap-4">
                <button
                  onClick={() => toggleFeature(key)}
                  disabled={saving}
                  className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 ${
                    value ? 'bg-blue-600' : 'bg-gray-200'
                  } ${saving ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}
                >
                  <span
                    className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform duration-200 ease-in-out ${
                      value ? 'translate-x-6' : 'translate-x-1'
                    }`}
                  />
                </button>
                <button
                  onClick={() => deleteFeature(key)}
                  disabled={saving}
                  className="text-red-500 hover:text-red-700 transition disabled:opacity-50"
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
          <h4 className="font-semibold text-blue-900">How it works</h4>
          <p className="text-sm text-blue-700 mt-1 leading-relaxed">
            Changes take effect immediately. iOS apps will receive the updated configuration within
            5 minutes (or on app restart). Use snake_case for feature keys (e.g., strava_enabled).
          </p>
        </div>
      </div>
    </div>
  )
}
