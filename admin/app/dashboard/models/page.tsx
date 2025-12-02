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
      <h2 className="text-2xl font-bold text-gray-900">AI Models & Rate Limits</h2>

      {error && <div className="bg-red-50 text-red-600 p-4 rounded-lg">{error}</div>}
      {success && <div className="bg-green-50 text-green-600 p-4 rounded-lg">{success}</div>}

      {/* Available Models Management */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-6 border-b border-gray-100 bg-gray-50/50 flex items-center justify-between">
          <div>
            <h3 className="text-lg font-bold text-gray-900">Available Models</h3>
            <p className="text-sm text-gray-500 mt-1">
              Manage AI models available for selection
            </p>
          </div>
          <button
            onClick={openAddForm}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors text-sm font-medium"
          >
            + Add Model
          </button>
        </div>

        <div className="divide-y divide-gray-100">
          {Object.entries(availableModels).map(([key, config]) => (
            <div
              key={key}
              className="p-4 flex items-center justify-between hover:bg-gray-50/50 transition-colors"
            >
              <div className="flex-1">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-sm bg-gray-100 px-2 py-0.5 rounded">{key}</span>
                  {config.requiresQuota && (
                    <span className="text-xs bg-yellow-100 text-yellow-700 px-2 py-0.5 rounded">
                      Premium
                    </span>
                  )}
                  {isDefaultModel(key) && (
                    <span className="text-xs bg-blue-100 text-blue-700 px-2 py-0.5 rounded">
                      Built-in
                    </span>
                  )}
                </div>
                <p className="font-medium text-gray-900 mt-1">{config.displayName}</p>
                <p className="text-sm text-gray-500">{config.modelId}</p>
                {config.description && (
                  <p className="text-xs text-gray-400 mt-1">{config.description}</p>
                )}
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => openEditForm(key)}
                  className="px-3 py-1.5 text-sm text-blue-600 hover:bg-blue-50 rounded transition-colors"
                >
                  Edit
                </button>
                {!isDefaultModel(key) && (
                  <button
                    onClick={() => deleteModel(key)}
                    disabled={saving}
                    className="px-3 py-1.5 text-sm text-red-600 hover:bg-red-50 rounded transition-colors disabled:opacity-50"
                  >
                    Delete
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Model Form Modal */}
      {showForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-md mx-4">
            <div className="p-6 border-b border-gray-100">
              <h3 className="text-lg font-bold text-gray-900">
                {editingKey ? 'Edit Model' : 'Add Model'}
              </h3>
            </div>
            <div className="p-6 space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Key <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={form.key}
                  onChange={(e) => setForm({ ...form, key: e.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, '_') })}
                  disabled={!!editingKey}
                  placeholder="e.g. GPT_4O"
                  className="w-full px-3 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Model ID <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={form.modelId}
                  onChange={(e) => setForm({ ...form, modelId: e.target.value })}
                  placeholder="e.g. openai/gpt-4o"
                  className="w-full px-3 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Display Name <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={form.displayName}
                  onChange={(e) => setForm({ ...form, displayName: e.target.value })}
                  placeholder="e.g. GPT-4o"
                  className="w-full px-3 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
                <input
                  type="text"
                  value={form.description}
                  onChange={(e) => setForm({ ...form, description: e.target.value })}
                  placeholder="e.g. OpenAI GPT-4o model"
                  className="w-full px-3 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>
              <div className="flex items-center gap-2">
                <input
                  type="checkbox"
                  id="requiresQuota"
                  checked={form.requiresQuota}
                  onChange={(e) => setForm({ ...form, requiresQuota: e.target.checked })}
                  className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
                />
                <label htmlFor="requiresQuota" className="text-sm text-gray-700">
                  Premium model (requires quota)
                </label>
              </div>
            </div>
            <div className="p-6 border-t border-gray-100 flex justify-end gap-3">
              <button
                onClick={closeForm}
                className="px-4 py-2 text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={saveModel}
                disabled={saving}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50"
              >
                {saving ? 'Saving...' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Model Mapping */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-6 border-b border-gray-100 bg-gray-50/50">
          <h3 className="text-lg font-bold text-gray-900">Model Mapping</h3>
          <p className="text-sm text-gray-500 mt-1">
            Configure which AI model handles each type of request
          </p>
        </div>

        <div className="divide-y divide-gray-100">
          {requestTypes.map((type) => (
            <div
              key={type.key}
              className="p-6 flex items-center justify-between hover:bg-gray-50/50 transition-colors"
            >
              <div className="flex-1 pr-8">
                <div className="flex items-center gap-2">
                  <span className="w-2 h-2 rounded-full bg-blue-500"></span>
                  <h4 className="font-semibold text-gray-900">{type.name}</h4>
                </div>
                <p className="text-sm text-gray-500 mt-1 ml-4">{type.description}</p>
              </div>

              <div className="relative">
                <select
                  value={models[type.key] || ''}
                  onChange={(e) => updateModel(type.key, e.target.value)}
                  disabled={saving}
                  className="appearance-none bg-white pl-4 pr-10 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm font-medium text-gray-700 shadow-sm hover:border-gray-300 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed min-w-[200px]"
                >
                  <option value="">Default Model</option>
                  {Object.entries(availableModels).map(([key, config]) => (
                    <option key={key} value={key} title={config.description}>
                      {config.displayName}
                      {config.requiresQuota && ' *'}
                    </option>
                  ))}
                </select>

                <div className="pointer-events-none absolute inset-y-0 right-0 flex items-center px-3 text-gray-500">
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

      {/* Rate Limits Configuration */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-6 border-b border-gray-100 bg-gray-50/50">
          <h3 className="text-lg font-bold text-gray-900">Rate Limits</h3>
          <p className="text-sm text-gray-500 mt-1">Configure API rate limiting thresholds</p>
        </div>

        <div className="p-8 grid grid-cols-1 md:grid-cols-3 gap-8">
          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">
              IP Limit <span className="text-gray-400 font-normal">(hourly)</span>
            </label>
            <div className="relative">
              <input
                type="number"
                value={rateLimits?.ipLimit || 100}
                onChange={(e) => updateRateLimit('ipLimit', Number.parseInt(e.target.value))}
                disabled={saving}
                className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all font-medium text-gray-900"
              />
              <div className="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
                <span className="text-gray-400 text-sm">req/h</span>
              </div>
            </div>
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">
              User Limit <span className="text-gray-400 font-normal">(monthly)</span>
            </label>
            <div className="relative">
              <input
                type="number"
                value={rateLimits?.userLimit || 1000}
                onChange={(e) => updateRateLimit('userLimit', Number.parseInt(e.target.value))}
                disabled={saving}
                className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all font-medium text-gray-900"
              />
              <div className="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
                <span className="text-gray-400 text-sm">req/mo</span>
              </div>
            </div>
          </div>

          <div>
            <label className="block text-sm font-semibold text-gray-700 mb-2">
              Premium Limit <span className="text-gray-400 font-normal">(daily)</span>
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
                <span className="text-gray-400 text-sm">req/d</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
