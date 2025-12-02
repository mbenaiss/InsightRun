'use client'

import { useEffect, useState } from 'react'
import { adminAPI, type BlockedEntity } from '@/lib/api'

export default function BlockedPage() {
  const [blockedUsers, setBlockedUsers] = useState<BlockedEntity[]>([])
  const [blockedIPs, setBlockedIPs] = useState<BlockedEntity[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  // New block form state
  const [newUserId, setNewUserId] = useState('')
  const [newIP, setNewIP] = useState('')
  const [blockReason, setBlockReason] = useState('')
  const [blocking, setBlocking] = useState(false)

  useEffect(() => {
    loadBlocked()
  }, [])

  const loadBlocked = async () => {
    try {
      const data = await adminAPI.getBlocked()
      setBlockedUsers(data.blockedUsers || [])
      setBlockedIPs(data.blockedIPs || [])
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load blocked entities')
    } finally {
      setLoading(false)
    }
  }

  const handleBlockUser = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newUserId) return

    setBlocking(true)
    setError('')

    try {
      await adminAPI.blockUser(newUserId, blockReason)
      setSuccess(`User ${newUserId} blocked`)
      setNewUserId('')
      setBlockReason('')
      await loadBlocked()
      setTimeout(() => setSuccess(''), 3000)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to block user')
    } finally {
      setBlocking(false)
    }
  }

  const handleBlockIP = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newIP) return

    setBlocking(true)
    setError('')

    try {
      await adminAPI.blockIP(newIP, blockReason)
      setSuccess(`IP ${newIP} blocked`)
      setNewIP('')
      setBlockReason('')
      await loadBlocked()
      setTimeout(() => setSuccess(''), 3000)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to block IP')
    } finally {
      setBlocking(false)
    }
  }

  const handleUnblockUser = async (userId: string) => {
    try {
      await adminAPI.unblockUser(userId)
      setSuccess(`User ${userId} unblocked`)
      await loadBlocked()
      setTimeout(() => setSuccess(''), 3000)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to unblock user')
    }
  }

  const handleUnblockIP = async (ip: string) => {
    try {
      await adminAPI.unblockIP(ip)
      setSuccess(`IP ${ip} unblocked`)
      await loadBlocked()
      setTimeout(() => setSuccess(''), 3000)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to unblock IP')
    }
  }

  const formatDate = (timestamp: number) => {
    return new Date(timestamp * 1000).toLocaleString()
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
      <h2 className="text-2xl font-bold text-gray-900">Blocked Users & IPs</h2>

      {error && <div className="bg-red-50 text-red-600 p-4 rounded-lg">{error}</div>}
      {success && <div className="bg-green-50 text-green-600 p-4 rounded-lg">{success}</div>}

      {/* Block Forms */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Block User Form */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 bg-red-50 text-red-600 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                />
              </svg>
            </div>
            <h3 className="text-lg font-bold text-gray-900">Block User</h3>
          </div>
          <form onSubmit={handleBlockUser} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">User ID</label>
              <input
                type="text"
                value={newUserId}
                onChange={(e) => setNewUserId(e.target.value)}
                placeholder="Enter user UUID..."
                className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-transparent transition outline-none"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Reason (optional)
              </label>
              <input
                type="text"
                value={blockReason}
                onChange={(e) => setBlockReason(e.target.value)}
                placeholder="Reason for blocking..."
                className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-transparent transition outline-none"
              />
            </div>
            <button
              type="submit"
              disabled={blocking || !newUserId}
              className="w-full bg-red-600 text-white py-2.5 rounded-lg hover:bg-red-700 transition shadow-sm hover:shadow disabled:opacity-50 font-medium"
            >
              {blocking ? 'Blocking...' : 'Block User'}
            </button>
          </form>
        </div>

        {/* Block IP Form */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 bg-orange-50 text-orange-600 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"
                />
              </svg>
            </div>
            <h3 className="text-lg font-bold text-gray-900">Block IP</h3>
          </div>
          <form onSubmit={handleBlockIP} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">IP Address</label>
              <input
                type="text"
                value={newIP}
                onChange={(e) => setNewIP(e.target.value)}
                placeholder="Enter IP address..."
                className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-transparent transition outline-none"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Reason (optional)
              </label>
              <input
                type="text"
                value={blockReason}
                onChange={(e) => setBlockReason(e.target.value)}
                placeholder="Reason for blocking..."
                className="w-full px-4 py-2.5 border border-gray-200 rounded-lg focus:ring-2 focus:ring-orange-500 focus:border-transparent transition outline-none"
              />
            </div>
            <button
              type="submit"
              disabled={blocking || !newIP}
              className="w-full bg-orange-600 text-white py-2.5 rounded-lg hover:bg-orange-700 transition shadow-sm hover:shadow disabled:opacity-50 font-medium"
            >
              {blocking ? 'Blocking...' : 'Block IP'}
            </button>
          </form>
        </div>
      </div>

      {/* Blocked Users List */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-6 border-b border-gray-100 bg-gray-50/50 flex justify-between items-center">
          <h3 className="text-lg font-bold text-gray-900">Blocked Users</h3>
          <span className="px-2.5 py-0.5 bg-gray-200 text-gray-700 rounded-full text-xs font-medium">
            {blockedUsers.length}
          </span>
        </div>
        {blockedUsers.length === 0 ? (
          <div className="p-12 text-center text-gray-500 flex flex-col items-center">
            <div className="w-16 h-16 bg-gray-50 rounded-full flex items-center justify-center mb-4 text-3xl">
              ✓
            </div>
            <p>No blocked users</p>
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {blockedUsers.map((user) => (
              <div
                key={user.id}
                className="p-4 flex items-center justify-between hover:bg-gray-50 transition"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <p className="font-mono text-sm font-medium text-gray-900 bg-gray-100 px-2 py-0.5 rounded">
                      {user.id}
                    </p>
                    <span className="px-2 py-0.5 bg-red-50 text-red-700 text-xs rounded-full border border-red-100">
                      Blocked
                    </span>
                  </div>
                  {user.reason && (
                    <p className="text-sm text-gray-600 mt-1">Reason: {user.reason}</p>
                  )}
                  <p className="text-xs text-gray-400 mt-1 flex items-center gap-1">
                    <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                    {formatDate(user.blocked_at)}
                  </p>
                </div>
                <button
                  onClick={() => handleUnblockUser(user.id)}
                  className="px-4 py-2 text-sm border border-gray-200 text-gray-600 rounded-lg hover:bg-gray-50 hover:text-gray-900 hover:border-gray-300 transition bg-white shadow-sm"
                >
                  Unblock
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Blocked IPs List */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-6 border-b border-gray-100 bg-gray-50/50 flex justify-between items-center">
          <h3 className="text-lg font-bold text-gray-900">Blocked IPs</h3>
          <span className="px-2.5 py-0.5 bg-gray-200 text-gray-700 rounded-full text-xs font-medium">
            {blockedIPs.length}
          </span>
        </div>
        {blockedIPs.length === 0 ? (
          <div className="p-12 text-center text-gray-500 flex flex-col items-center">
            <div className="w-16 h-16 bg-gray-50 rounded-full flex items-center justify-center mb-4 text-3xl">
              ✓
            </div>
            <p>No blocked IPs</p>
          </div>
        ) : (
          <div className="divide-y divide-gray-100">
            {blockedIPs.map((ip) => (
              <div
                key={ip.id}
                className="p-4 flex items-center justify-between hover:bg-gray-50 transition"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <p className="font-mono text-sm font-medium text-gray-900 bg-gray-100 px-2 py-0.5 rounded">
                      {ip.id}
                    </p>
                    <span className="px-2 py-0.5 bg-orange-50 text-orange-700 text-xs rounded-full border border-orange-100">
                      Blocked
                    </span>
                  </div>
                  {ip.reason && <p className="text-sm text-gray-600 mt-1">Reason: {ip.reason}</p>}
                  <p className="text-xs text-gray-400 mt-1 flex items-center gap-1">
                    <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                    {formatDate(ip.blocked_at)}
                  </p>
                </div>
                <button
                  onClick={() => handleUnblockIP(ip.id)}
                  className="px-4 py-2 text-sm border border-gray-200 text-gray-600 rounded-lg hover:bg-gray-50 hover:text-gray-900 hover:border-gray-300 transition bg-white shadow-sm"
                >
                  Unblock
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
