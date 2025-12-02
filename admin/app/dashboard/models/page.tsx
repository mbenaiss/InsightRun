'use client'

import { useEffect, useState } from 'react'
import { adminAPI, type ModelConfig, type RateLimitsConfig } from '@/lib/api'

const requestTypes = [
  { key: 'SIMPLE', name: 'Simple Queries', description: 'Basic questions and quick answers' },
  {
    key: 'MODERATE',
    name: 'Moderate Analysis',
    description: 'Workout analysis and recommendations',
  },
  { key: 'COMPLEX', name: 'Complex Analysis', description: 'Deep historical analysis' },
  {
    key: 'WORKOUT_GENERATION',
    name: 'Workout Generation',
    description: 'Creating custom workout plans',
  },
  { key: 'BATCH_PROCESSING', name: 'Batch Processing', description: 'Historical data processing' },
  {
    key: 'SMART_SUGGESTION',
    name: 'Smart Suggestions',
    description: 'Intelligent recommendations',
  },
  { key: 'CLASSIFICATION', name: 'Classification', description: 'Request type classification' },
]

interface ModelFormData {
  key: string
  modelId: string
  displayName: string
  description: string
  requiresQuota: boolean
}

const emptyForm: ModelFormData = {
  key: '',
  modelId: '',
  displayName: '',
  description: '',
  requiresQuota: false,
}

export default function ModelsPage() {
  const [models, setModels] = useState<Record<string, string>>({})
  const [availableModels, setAvailableModels] = useState<Record<string, ModelConfig>>({})
  const [defaultModels, setDefaultModels] = useState<Record<string, ModelConfig>>({})
  const [rateLimits, setRateLimits] = useState<RateLimitsConfig | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const [showForm, setShowForm] = useState(false)
  const [editingKey, setEditingKey] = useState<string | null>(null)
  const [form, setForm] = useState<ModelFormData>(emptyForm)

  useEffect(() => {
    loadConfig()
  }, [])

  const loadConfig = async () => {
    try {
      const config = await adminAPI.getConfig()
      setModels(config.models.current || {})
      setAvailableModels(config.models.available || {})
      setDefaultModels(config.models.defaultModels || {})
      setRateLimits(config.rate_limits.current)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load config')
    } finally {
      setLoading(false)
    }
  }

  const updateModel = async (requestType: string, model: string) => {
    const previousModels = { ...models }
    setModels({ ...models, [requestType]: model })
    setError('')
    setSuccess('')
    setSaving(true)

    try {
      await adminAPI.updateModels({ ...models, [requestType]: model })
      setSuccess(`Model for ${requestType} updated`)
      setTimeout(() => setSuccess(''), 3000)
    } catch (e) {
      setModels(previousModels)
      setError(e instanceof Error ? e.message : 'Failed to update model')
    } finally {
      setSaving(false)
    }
  }

  const updateRateLimit = async (key: keyof RateLimitsConfig, value: number) => {
    if (!rateLimits) return

    const previousLimits = { ...rateLimits }
    setRateLimits({ ...rateLimits, [key]: value })
    setError('')
    setSuccess('')
    setSaving(true)

    try {
      await adminAPI.updateRateLimits({ [key]: value })
      setSuccess(`Rate limit updated`)
      setTimeout(() => setSuccess(''), 3000)
    } catch (e) {
      setRateLimits(previousLimits)
      setError(e instanceof Error ? e.message : 'Failed to update rate limit')
    } finally {
      setSaving(false)
    }
  }

  const openAddForm = () => {
    setForm(emptyForm)
    setEditingKey(null)
    setShowForm(true)
  }

  const openEditForm = (key: string) => {
    const model = availableModels[key]
    if (model) {
      setForm({
        key,
        modelId: model.modelId,
        displayName: model.displayName,
        description: model.description,
        requiresQuota: model.requiresQuota,
      })
      setEditingKey(key)
      setShowForm(true)
    }
  }

  const closeForm = () => {
    setShowForm(false)
    setEditingKey(null)
    setForm(emptyForm)
  }

  const saveModel = async () => {
    if (!form.key || !form.modelId || !form.displayName) {
      setError('Key, Model ID and Display Name are required')
      return
    }

    setSaving(true)
    setError('')

    try {
      await adminAPI.upsertModel(form.key, {
        modelId: form.modelId,
        displayName: form.displayName,
        description: form.description,
        requiresQuota: form.requiresQuota,
      })
      setSuccess(`Model ${form.key} saved`)
      setTimeout(() => setSuccess(''), 3000)
      closeForm()
      await loadConfig()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to save model')
    } finally {
      setSaving(false)
    }
  }

  const deleteModel = async (key: string) => {
    if (!confirm(`Delete model "${key}"?`)) return

    setSaving(true)
    setError('')

    try {
      await adminAPI.deleteModel(key)
      setSuccess(`Model ${key} deleted`)
      setTimeout(() => setSuccess(''), 3000)
      await loadConfig()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to delete model')
    } finally {
      setSaving(false)
    }
  }

  const isDefaultModel = (key: string) => key in defaultModels

  if (loading) {
    return (
      <div className="flex justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
      </div>
    )
  }

  return (
    <div className="space-y-8">
      {/* Header with Gradient */}
      <div className="relative bg-gradient-to-r from-purple-900 to-indigo-900 rounded-2xl p-8 text-white shadow-lg overflow-hidden">
        <div className="absolute top-0 right-0 p-4 opacity-10">
          <svg className="w-64 h-64 transform -rotate-12" fill="currentColor" viewBox="0 0 24 24">
            <path d="M19.428 15.428a2 2 0 00-1.022-.547l-2.384-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z" />
          </svg>
        </div>
        <div className="relative z-10">
          <h2 className="text-3xl font-bold mb-2">AI Models & Configuration</h2>
          <p className="text-purple-200 max-w-2xl">
            Manage the intelligence behind InsightRun. Configure available models, assign them to
            specific tasks, and control usage limits.
          </p>
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

      {/* Available Models Grid */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-xl font-bold text-gray-900 flex items-center gap-2">
            <span className="w-1 h-6 bg-blue-500 rounded-full"></span>
            Available Models
          </h3>
          <button
            onClick={openAddForm}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-all shadow-sm hover:shadow font-medium"
          >
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 4v16m8-8H4"
              />
            </svg>
            Add Model
          </button>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {Object.entries(availableModels).map(([key, config]) => (
            <div
              key={key}
              className="group bg-white rounded-xl shadow-sm border border-gray-100 p-5 hover:shadow-md transition-all duration-200 relative overflow-hidden"
            >
              <div
                className={`absolute top-0 left-0 w-1 h-full ${config.requiresQuota ? 'bg-amber-400' : 'bg-blue-400'}`}
              ></div>

              <div className="flex justify-between items-start mb-3 pl-3">
                <div>
                  <h4 className="font-bold text-gray-900 text-lg">{config.displayName}</h4>
                  <code className="text-xs text-gray-500 bg-gray-50 px-1.5 py-0.5 rounded mt-1 inline-block">
                    {key}
                  </code>
                </div>
                <div className="flex gap-1">
                  <button
                    onClick={() => openEditForm(key)}
                    className="p-1.5 text-gray-400 hover:text-blue-600 hover:bg-blue-50 rounded-lg transition-colors"
                    title="Edit"
                  >
                    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                      />
                    </svg>
                  </button>
                  {!isDefaultModel(key) && (
                    <button
                      onClick={() => deleteModel(key)}
                      disabled={saving}
                      className="p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                      title="Delete"
                    >
                      <svg
                        className="w-4 h-4"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                        />
                      </svg>
                    </button>
                  )}
                </div>
              </div>

              <p className="text-sm text-gray-600 mb-4 pl-3 line-clamp-2 min-h-[2.5rem]">
                {config.description || 'No description provided'}
              </p>

              <div className="pl-3 flex flex-wrap gap-2">
                {config.requiresQuota && (
                  <span className="inline-flex items-center gap-1 px-2 py-1 rounded-md bg-amber-50 text-amber-700 text-xs font-medium">
                    <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M13 10V3L4 14h7v7l9-11h-7z"
                      />
                    </svg>
                    Premium
                  </span>
                )}
                {isDefaultModel(key) && (
                  <span className="inline-flex items-center gap-1 px-2 py-1 rounded-md bg-blue-50 text-blue-700 text-xs font-medium">
                    <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                    Built-in
                  </span>
                )}
                <span className="inline-flex items-center gap-1 px-2 py-1 rounded-md bg-gray-100 text-gray-600 text-xs font-medium truncate max-w-[150px]">
                  ID: {config.modelId}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Configuration Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Model Mapping */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden flex flex-col h-full">
          <div className="px-6 py-4 border-b border-gray-100 bg-gray-50/30">
            <h3 className="text-lg font-bold text-gray-900 flex items-center gap-2">
              <span className="w-1 h-5 bg-purple-500 rounded-full"></span>
              Request Routing
            </h3>
            <p className="text-sm text-gray-500 mt-1">Route specific tasks to optimized models</p>
          </div>
          <div className="divide-y divide-gray-100 flex-1">
            {requestTypes.map((type) => (
              <div
                key={type.key}
                className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4 hover:bg-gray-50/50 transition-colors"
              >
                <div className="flex-1">
                  <h4 className="font-medium text-gray-900 text-sm">{type.name}</h4>
                  <p className="text-xs text-gray-500">{type.description}</p>
                </div>
                <div className="relative min-w-[200px]">
                  <select
                    value={models[type.key] || ''}
                    onChange={(e) => updateModel(type.key, e.target.value)}
                    disabled={saving}
                    className="w-full appearance-none bg-white pl-3 pr-8 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent text-sm text-gray-700 shadow-sm hover:border-gray-300 transition-colors cursor-pointer disabled:opacity-50"
                  >
                    <option value="">Default Model</option>
                    {Object.entries(availableModels).map(([key, config]) => (
                      <option key={key} value={key}>
                        {config.displayName} {config.requiresQuota ? '(Premium)' : ''}
                      </option>
                    ))}
                  </select>
                  <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center px-2 text-gray-500">
                    <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M19 9l-7 7-7-7"
                      />
                    </svg>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Rate Limits */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden flex flex-col h-full">
          <div className="px-6 py-4 border-b border-gray-100 bg-gray-50/30">
            <h3 className="text-lg font-bold text-gray-900 flex items-center gap-2">
              <span className="w-1 h-5 bg-amber-500 rounded-full"></span>
              Safety Limits
            </h3>
            <p className="text-sm text-gray-500 mt-1">Control API consumption quotas</p>
          </div>
          <div className="p-6 space-y-6 flex-1">
            <div className="group">
              <label className="flex items-center gap-2 text-sm font-semibold text-gray-700 mb-2">
                <svg
                  className="w-4 h-4 text-amber-500"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
                  />
                </svg>
                IP Address Limit
              </label>
              <div className="relative">
                <input
                  type="number"
                  value={rateLimits?.ipLimit || 100}
                  onChange={(e) => updateRateLimit('ipLimit', Number.parseInt(e.target.value))}
                  disabled={saving}
                  className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-amber-500 focus:border-transparent transition-all font-medium text-gray-900"
                />
                <div className="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
                  <span className="text-gray-400 text-sm">req / hour</span>
                </div>
              </div>
              <p className="text-xs text-gray-500 mt-1.5">
                Prevents abuse from single IP addresses.
              </p>
            </div>

            <div className="group">
              <label className="flex items-center gap-2 text-sm font-semibold text-gray-700 mb-2">
                <svg
                  className="w-4 h-4 text-purple-500"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                  />
                </svg>
                User Limit
              </label>
              <div className="relative">
                <input
                  type="number"
                  value={rateLimits?.userLimit || 1000}
                  onChange={(e) => updateRateLimit('userLimit', Number.parseInt(e.target.value))}
                  disabled={saving}
                  className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent transition-all font-medium text-gray-900"
                />
                <div className="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
                  <span className="text-gray-400 text-sm">req / month</span>
                </div>
              </div>
              <p className="text-xs text-gray-500 mt-1.5">
                Standard monthly quota per user account.
              </p>
            </div>

            <div className="group">
              <label className="flex items-center gap-2 text-sm font-semibold text-gray-700 mb-2">
                <svg
                  className="w-4 h-4 text-blue-500"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M13 10V3L4 14h7v7l9-11h-7z"
                  />
                </svg>
                Premium Model Limit
              </label>
              <div className="relative">
                <input
                  type="number"
                  value={rateLimits?.premiumModelLimit || 20}
                  onChange={(e) =>
                    updateRateLimit('premiumModelLimit', Number.parseInt(e.target.value))
                  }
                  disabled={saving}
                  className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all font-medium text-gray-900"
                />
                <div className="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
                  <span className="text-gray-400 text-sm">req / day</span>
                </div>
              </div>
              <p className="text-xs text-gray-500 mt-1.5">
                Daily cap for expensive premium models.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Model Form Modal */}
      {showForm && (
        <div className="fixed inset-0 bg-slate-900/20 backdrop-blur-sm flex items-center justify-center z-50 transition-opacity">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-lg mx-4 transform transition-all scale-100">
            <div className="p-6 border-b border-gray-100 flex justify-between items-center">
              <h3 className="text-xl font-bold text-gray-900">
                {editingKey ? 'Edit Model' : 'Add New Model'}
              </h3>
              <button
                onClick={closeForm}
                className="text-gray-400 hover:text-gray-600 transition-colors"
              >
                <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>
            <div className="p-6 space-y-5">
              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                  Internal Key <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={form.key}
                  onChange={(e) =>
                    setForm({
                      ...form,
                      key: e.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, '_'),
                    })
                  }
                  disabled={!!editingKey}
                  placeholder="e.g. GEMINI_PRO"
                  className="w-full px-4 py-2.5 border border-gray-200 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-50 disabled:text-gray-500 transition-all"
                />
                <p className="text-xs text-gray-400 mt-1">
                  Unique identifier, uppercase with underscores.
                </p>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                    Provider ID <span className="text-red-500">*</span>
                  </label>
                  <input
                    type="text"
                    value={form.modelId}
                    onChange={(e) => setForm({ ...form, modelId: e.target.value })}
                    placeholder="e.g. gemini-1.5-pro"
                    className="w-full px-4 py-2.5 border border-gray-200 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                  />
                </div>
                <div>
                  <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                    Display Name <span className="text-red-500">*</span>
                  </label>
                  <input
                    type="text"
                    value={form.displayName}
                    onChange={(e) => setForm({ ...form, displayName: e.target.value })}
                    placeholder="e.g. Gemini Pro"
                    className="w-full px-4 py-2.5 border border-gray-200 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                  Description
                </label>
                <textarea
                  value={form.description}
                  onChange={(e) => setForm({ ...form, description: e.target.value })}
                  placeholder="Brief description of the model's capabilities..."
                  rows={3}
                  className="w-full px-4 py-2.5 border border-gray-200 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all resize-none"
                />
              </div>

              <div className="bg-gray-50 p-4 rounded-xl border border-gray-100 flex items-center gap-3">
                <div className="flex items-center h-5">
                  <input
                    type="checkbox"
                    id="requiresQuota"
                    checked={form.requiresQuota}
                    onChange={(e) => setForm({ ...form, requiresQuota: e.target.checked })}
                    className="w-5 h-5 text-blue-600 border-gray-300 rounded focus:ring-blue-500 transition-colors cursor-pointer"
                  />
                </div>
                <label
                  htmlFor="requiresQuota"
                  className="text-sm text-gray-700 cursor-pointer select-none"
                >
                  <span className="font-semibold block">Premium Model</span>
                  <span className="text-gray-500 text-xs">
                    Counts against the daily premium limit quota.
                  </span>
                </label>
              </div>
            </div>
            <div className="p-6 border-t border-gray-100 bg-gray-50/50 flex justify-end gap-3 rounded-b-2xl">
              <button
                onClick={closeForm}
                className="px-5 py-2.5 text-gray-700 hover:bg-white hover:shadow-sm border border-transparent hover:border-gray-200 rounded-xl transition-all font-medium"
              >
                Cancel
              </button>
              <button
                onClick={saveModel}
                disabled={saving}
                className="px-6 py-2.5 bg-blue-600 text-white rounded-xl hover:bg-blue-700 shadow-lg shadow-blue-600/20 hover:shadow-blue-600/40 transition-all disabled:opacity-50 font-medium transform hover:-translate-y-0.5 active:translate-y-0"
              >
                {saving ? 'Saving...' : 'Save Configuration'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
