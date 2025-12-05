const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'https://api.insightrun.altcode.studio'

export interface ModelConfig {
  modelId: string
  displayName: string
  description: string
  requiresQuota: boolean
}

export interface ModelsConfig {
  current: Record<string, string>
  available: Record<string, ModelConfig>
  defaults: Record<string, string>
  defaultModels: Record<string, ModelConfig>
}

export interface RateLimitsResponse {
  current: RateLimitsConfig
  defaults: RateLimitsConfig
}

export interface AdminConfig {
  features: FeatureFlags
  models: ModelsConfig
  rate_limits: RateLimitsResponse
}

export type FeatureFlags = Record<string, boolean>

export interface ModelMapping {
  [key: string]: string
}

export interface RateLimitsConfig {
  ipLimit: number
  ipWindow: number
  userLimit: number
  userWindow: number
  premiumModelLimit: number
}

export interface BlockedEntity {
  id: string
  type: 'user' | 'ip'
  reason?: string
  blocked_at: number
  blocked_by?: string
  expires_at?: number | null
}

class AdminAPI {
  private adminSecret: string | null = null

  setAdminSecret(secret: string) {
    this.adminSecret = secret
  }

  private getHeaders(): HeadersInit {
    if (!this.adminSecret) {
      throw new Error('Admin secret not set')
    }
    return {
      'Content-Type': 'application/json',
      'X-Admin-Key': this.adminSecret,
    }
  }

  async getConfig(): Promise<AdminConfig> {
    const response = await fetch(`${API_BASE_URL}/api/admin/config`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      if (response.status === 401) {
        throw new Error('Invalid admin credentials')
      }
      throw new Error(`Failed to fetch config: ${response.status}`)
    }

    return response.json()
  }

  async updateFeatures(features: Partial<FeatureFlags>): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/config/features`, {
      method: 'PUT',
      headers: this.getHeaders(),
      body: JSON.stringify(features),
    })

    if (!response.ok) {
      throw new Error(`Failed to update features: ${response.status}`)
    }
  }

  async setAllFeatures(features: FeatureFlags): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/config/features`, {
      method: 'PUT',
      headers: this.getHeaders(),
      body: JSON.stringify({ _replace_all: true, ...features }),
    })

    if (!response.ok) {
      throw new Error(`Failed to set features: ${response.status}`)
    }
  }

  async updateModels(models: ModelMapping): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/config/models`, {
      method: 'PUT',
      headers: this.getHeaders(),
      body: JSON.stringify(models),
    })

    if (!response.ok) {
      throw new Error(`Failed to update models: ${response.status}`)
    }
  }

  async upsertModel(key: string, config: ModelConfig): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/models/${encodeURIComponent(key)}`, {
      method: 'PUT',
      headers: this.getHeaders(),
      body: JSON.stringify(config),
    })

    if (!response.ok) {
      throw new Error(`Failed to save model: ${response.status}`)
    }
  }

  async deleteModel(key: string): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/models/${encodeURIComponent(key)}`, {
      method: 'DELETE',
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      throw new Error(data.message || `Failed to delete model: ${response.status}`)
    }
  }

  async updateRateLimits(limits: Partial<RateLimitsConfig>): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/config/rate-limits`, {
      method: 'PUT',
      headers: this.getHeaders(),
      body: JSON.stringify(limits),
    })

    if (!response.ok) {
      throw new Error(`Failed to update rate limits: ${response.status}`)
    }
  }

  async blockUser(userId: string, reason?: string): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/users/${userId}/block`, {
      method: 'POST',
      headers: this.getHeaders(),
      body: JSON.stringify({ reason }),
    })

    if (!response.ok) {
      throw new Error(`Failed to block user: ${response.status}`)
    }
  }

  async unblockUser(userId: string): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/users/${userId}/block`, {
      method: 'DELETE',
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to unblock user: ${response.status}`)
    }
  }

  async blockIP(ip: string, reason?: string): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/ip/${encodeURIComponent(ip)}/block`, {
      method: 'POST',
      headers: this.getHeaders(),
      body: JSON.stringify({ reason }),
    })

    if (!response.ok) {
      throw new Error(`Failed to block IP: ${response.status}`)
    }
  }

  async unblockIP(ip: string): Promise<void> {
    const response = await fetch(`${API_BASE_URL}/api/admin/ip/${encodeURIComponent(ip)}/block`, {
      method: 'DELETE',
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to unblock IP: ${response.status}`)
    }
  }

  async getBlocked(): Promise<{ blockedUsers: BlockedEntity[]; blockedIPs: BlockedEntity[] }> {
    const response = await fetch(`${API_BASE_URL}/api/admin/blocked`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch blocked entities: ${response.status}`)
    }

    return response.json()
  }
}

export const adminAPI = new AdminAPI()
