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
      {/* Hero Header */}
      <div className="relative bg-gradient-to-r from-rose-900 to-red-900 rounded-2xl p-8 text-white shadow-lg overflow-hidden">
        <div className="absolute top-0 right-0 p-4 opacity-10">
          <svg className="w-64 h-64 transform -rotate-12" fill="currentColor" viewBox="0 0 24 24">
            <path
              fillRule="evenodd"
              d="M10 1.944A11.954 11.954 0 012.166 5C2.056 5.649 2 6.319 2 7c0 5.225 3.34 9.67 8 11.317C14.66 16.67 18 12.225 18 7c0-.682-.057-1.35-.166-2.001A11.954 11.954 0 0110 1.944zM11 14a1 1 0 11-2 0 1 1 0 012 0zm0-7a1 1 0 10-2 0v3a1 1 0 102 0V7z"
              clipRule="evenodd"
            />
          </svg>
        </div>
        <div className="relative z-10">
          <h2 className="text-3xl font-bold mb-2">Access Control</h2>
          <p className="text-rose-100 max-w-2xl leading-relaxed">
            Manage blocked users and IP addresses to protect the platform from abuse. Blocked
            entities will be immediately denied access to the API.
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

      {/* Block Forms */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Block User Form */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 flex flex-col h-full">
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
            <div>
              <h3 className="text-lg font-bold text-gray-900">Block User</h3>
              <p className="text-xs text-gray-500">Ban a specific user ID</p>
            </div>
          </div>
          <form onSubmit={handleBlockUser} className="space-y-4 flex-1 flex flex-col">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">User ID</label>
              <input
                type="text"
                value={newUserId}
                onChange={(e) => setNewUserId(e.target.value)}
                placeholder="Enter user UUID..."
                className="w-full px-4 py-2.5 border border-gray-200 rounded-xl focus:ring-2 focus:ring-red-500 focus:border-transparent transition outline-none text-sm"
              />
            </div>
            <div className="flex-1">
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                Reason <span className="font-normal text-gray-400">(optional)</span>
              </label>
              <input
                type="text"
                value={blockReason}
                onChange={(e) => setBlockReason(e.target.value)}
                placeholder="Violation of terms, spam..."
                className="w-full px-4 py-2.5 border border-gray-200 rounded-xl focus:ring-2 focus:ring-red-500 focus:border-transparent transition outline-none text-sm"
              />
            </div>
            <button
              type="submit"
              disabled={blocking || !newUserId}
              className="w-full bg-red-600 text-white py-2.5 rounded-xl hover:bg-red-700 transition shadow-lg shadow-red-600/20 hover:shadow-red-600/40 disabled:opacity-50 font-medium transform active:scale-[0.98]"
            >
              {blocking ? 'Blocking...' : 'Block User'}
            </button>
          </form>
        </div>

        {/* Block IP Form */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 flex flex-col h-full">
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
            <div>
              <h3 className="text-lg font-bold text-gray-900">Block IP</h3>
              <p className="text-xs text-gray-500">Ban a specific IP address</p>
            </div>
          </div>
          <form onSubmit={handleBlockIP} className="space-y-4 flex-1 flex flex-col">
            <div>
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">IP Address</label>
              <input
                type="text"
                value={newIP}
                onChange={(e) => setNewIP(e.target.value)}
                placeholder="e.g. 192.168.1.1"
                className="w-full px-4 py-2.5 border border-gray-200 rounded-xl focus:ring-2 focus:ring-orange-500 focus:border-transparent transition outline-none text-sm"
              />
            </div>
            <div className="flex-1">
              <label className="block text-sm font-semibold text-gray-700 mb-1.5">
                Reason <span className="font-normal text-gray-400">(optional)</span>
              </label>
              <input
                type="text"
                value={blockReason}
                onChange={(e) => setBlockReason(e.target.value)}
                placeholder="DDoS attempt, scraping..."
                className="w-full px-4 py-2.5 border border-gray-200 rounded-xl focus:ring-2 focus:ring-orange-500 focus:border-transparent transition outline-none text-sm"
              />
            </div>
            <button
              type="submit"
              disabled={blocking || !newIP}
              className="w-full bg-orange-600 text-white py-2.5 rounded-xl hover:bg-orange-700 transition shadow-lg shadow-orange-600/20 hover:shadow-orange-600/40 disabled:opacity-50 font-medium transform active:scale-[0.98]"
            >
              {blocking ? 'Blocking...' : 'Block IP'}
            </button>
          </form>
        </div>
      </div>

      {/* Blocked Users List */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-6 border-b border-gray-100 bg-gray-50/50 flex justify-between items-center">
          <h3 className="text-lg font-bold text-gray-900 flex items-center gap-2">
            <span className="w-1 h-5 bg-red-500 rounded-full"></span>
            Blocked Users
          </h3>
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
                className="p-4 flex flex-col sm:flex-row sm:items-center justify-between hover:bg-gray-50 transition gap-4"
              >
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <p className="font-mono text-sm font-medium text-gray-900 bg-gray-100 px-2 py-0.5 rounded border border-gray-200">
                      {user.id}
                    </p>
                    <span className="px-2 py-0.5 bg-red-50 text-red-700 text-xs font-medium rounded-full border border-red-100">
                      Active Ban
                    </span>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-gray-500">
                    <span className="flex items-center gap-1">
                      <svg
                        className="w-3 h-3"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                      {formatDate(user.blocked_at)}
                    </span>
                    {user.reason && (
                      <span className="flex items-center gap-1 text-gray-600">
                        <span className="w-1 h-1 bg-gray-300 rounded-full"></span>
                        Reason: {user.reason}
                      </span>
                    )}
                  </div>
                </div>
                <button
                  onClick={() => handleUnblockUser(user.id)}
                  className="px-4 py-2 text-sm font-medium text-gray-600 bg-white border border-gray-200 rounded-lg hover:bg-gray-50 hover:text-gray-900 hover:border-gray-300 transition shadow-sm whitespace-nowrap"
                >
                  Unblock User
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Blocked IPs List */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="p-6 border-b border-gray-100 bg-gray-50/50 flex justify-between items-center">
          <h3 className="text-lg font-bold text-gray-900 flex items-center gap-2">
            <span className="w-1 h-5 bg-orange-500 rounded-full"></span>
            Blocked IPs
          </h3>
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
                className="p-4 flex flex-col sm:flex-row sm:items-center justify-between hover:bg-gray-50 transition gap-4"
              >
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <p className="font-mono text-sm font-medium text-gray-900 bg-gray-100 px-2 py-0.5 rounded border border-gray-200">
                      {ip.id}
                    </p>
                    <span className="px-2 py-0.5 bg-orange-50 text-orange-700 text-xs font-medium rounded-full border border-orange-100">
                      Active Ban
                    </span>
                  </div>
                  <div className="flex items-center gap-4 text-xs text-gray-500">
                    <span className="flex items-center gap-1">
                      <svg
                        className="w-3 h-3"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth={2}
                          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                      {formatDate(ip.blocked_at)}
                    </span>
                    {ip.reason && (
                      <span className="flex items-center gap-1 text-gray-600">
                        <span className="w-1 h-1 bg-gray-300 rounded-full"></span>
                        Reason: {ip.reason}
                      </span>
                    )}
                  </div>
                </div>
                <button
                  onClick={() => handleUnblockIP(ip.id)}
                  className="px-4 py-2 text-sm font-medium text-gray-600 bg-white border border-gray-200 rounded-lg hover:bg-gray-50 hover:text-gray-900 hover:border-gray-300 transition shadow-sm whitespace-nowrap"
                >
                  Unblock IP
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
