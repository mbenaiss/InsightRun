/**
 * InsightRun Backend - Strava Integration with Webhooks
 *
 * This backend handles:
 * 1. OAuth token exchange (Client Secret stays server-side - SECURE)
 * 2. Strava Webhooks (real-time activity notifications)
 * 3. Push notifications to iOS app
 *
 * Deploy to: Railway, Render, Fly.io, or Cloudflare Workers
 *
 * Environment Variables Required:
 * - STRAVA_CLIENT_ID
 * - STRAVA_CLIENT_SECRET
 * - STRAVA_WEBHOOK_VERIFY_TOKEN (a random string you choose)
 * - DATABASE_URL (PostgreSQL for user tokens)
 * - APNS_KEY_ID (for iOS push notifications)
 * - APNS_TEAM_ID
 */

import express from 'express';
import axios from 'axios';
import crypto from 'crypto';

const app = express();
app.use(express.json());

// Environment variables
const STRAVA_CLIENT_ID = process.env.STRAVA_CLIENT_ID;
const STRAVA_CLIENT_SECRET = process.env.STRAVA_CLIENT_SECRET;
const STRAVA_WEBHOOK_VERIFY_TOKEN = process.env.STRAVA_WEBHOOK_VERIFY_TOKEN || 'INSIGHTRUN_STRAVA';
const PORT = process.env.PORT || 3000;

// In-memory storage for demo (use PostgreSQL/Redis in production)
const userTokens = new Map();

// ============================================
// 1. OAUTH TOKEN EXCHANGE (SECURE)
// ============================================

/**
 * Exchange authorization code for tokens
 * Called by iOS app instead of doing it directly
 * This keeps Client Secret server-side (SECURE)
 */
app.post('/api/strava/exchange-token', async (req, res) => {
  const { code, userId } = req.body;

  if (!code || !userId) {
    return res.status(400).json({ error: 'Missing code or userId' });
  }

  try {
    // Exchange code for tokens with Strava
    const response = await axios.post('https://www.strava.com/oauth/token', {
      client_id: STRAVA_CLIENT_ID,
      client_secret: STRAVA_CLIENT_SECRET, // SECURE: Never exposed to iOS
      code: code,
      grant_type: 'authorization_code'
    });

    const { access_token, refresh_token, expires_at, athlete } = response.data;

    // Store tokens securely (use encrypted DB in production)
    userTokens.set(userId, {
      accessToken: access_token,
      refreshToken: refresh_token,
      expiresAt: expires_at,
      athleteId: athlete.id,
      deviceTokens: [] // For push notifications
    });

    console.log(`✅ Token exchanged for user ${userId} (athlete: ${athlete.id})`);

    // Return tokens to iOS (iOS will store in Keychain)
    res.json({
      accessToken: access_token,
      refreshToken: refresh_token,
      expiresAt: expires_at,
      athlete: athlete
    });
  } catch (error) {
    console.error('❌ Token exchange failed:', error.response?.data || error.message);
    res.status(500).json({ error: 'Token exchange failed' });
  }
});

/**
 * Refresh access token
 * Called by iOS app when token expires
 */
app.post('/api/strava/refresh-token', async (req, res) => {
  const { refreshToken, userId } = req.body;

  if (!refreshToken || !userId) {
    return res.status(400).json({ error: 'Missing refreshToken or userId' });
  }

  try {
    const response = await axios.post('https://www.strava.com/oauth/token', {
      client_id: STRAVA_CLIENT_ID,
      client_secret: STRAVA_CLIENT_SECRET, // SECURE: Server-side only
      refresh_token: refreshToken,
      grant_type: 'refresh_token'
    });

    const { access_token, refresh_token, expires_at } = response.data;

    // Update stored tokens
    const userData = userTokens.get(userId);
    if (userData) {
      userData.accessToken = access_token;
      userData.refreshToken = refresh_token;
      userData.expiresAt = expires_at;
      userTokens.set(userId, userData);
    }

    console.log(`🔄 Token refreshed for user ${userId}`);

    res.json({
      accessToken: access_token,
      refreshToken: refresh_token,
      expiresAt: expires_at
    });
  } catch (error) {
    console.error('❌ Token refresh failed:', error.response?.data || error.message);
    res.status(500).json({ error: 'Token refresh failed' });
  }
});

// ============================================
// 2. STRAVA WEBHOOKS (THE CRITICAL PART!)
// ============================================

/**
 * Webhook verification (GET request from Strava)
 * Strava sends this to verify your endpoint before activating it
 */
app.get('/api/webhooks/strava', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  console.log('🔍 Webhook verification request:', { mode, token, challenge });

  // Verify token matches
  if (mode === 'subscribe' && token === STRAVA_WEBHOOK_VERIFY_TOKEN) {
    console.log('✅ Webhook verified');
    res.json({ 'hub.challenge': challenge });
  } else {
    console.log('❌ Webhook verification failed');
    res.status(403).send('Forbidden');
  }
});

/**
 * Webhook events (POST request from Strava)
 * This is called when a new activity is created/updated
 *
 * THE MAGIC: Instead of polling, Strava tells you!
 */
app.post('/api/webhooks/strava', async (req, res) => {
  const event = req.body;

  console.log('📨 Webhook event received:', JSON.stringify(event, null, 2));

  // Respond immediately (Strava requires fast response)
  res.status(200).send('EVENT_RECEIVED');

  // Process event asynchronously
  processStravaEvent(event);
});

async function processStravaEvent(event) {
  const { object_type, aspect_type, object_id, owner_id, updates } = event;

  // We only care about new/updated activities
  if (object_type !== 'activity') {
    console.log('⏭️  Skipping non-activity event');
    return;
  }

  if (aspect_type === 'create') {
    console.log(`🆕 New activity created: ${object_id} by athlete ${owner_id}`);

    // Find user by athlete ID
    const user = findUserByAthleteId(owner_id);
    if (!user) {
      console.log('⚠️  User not found for athlete', owner_id);
      return;
    }

    // Fetch activity details
    try {
      const activity = await fetchActivityDetails(user, object_id);

      // Send push notification to iOS app
      await sendPushNotification(user, {
        title: '🏃 New Activity Synced',
        body: `${activity.name} - ${(activity.distance / 1000).toFixed(1)} km`,
        data: {
          activityId: object_id,
          type: 'new_activity'
        }
      });

      console.log('✅ Activity processed and notification sent');
    } catch (error) {
      console.error('❌ Error processing activity:', error.message);
    }
  } else if (aspect_type === 'update') {
    console.log(`🔄 Activity updated: ${object_id}`);
    // Handle activity updates (e.g., title change, privacy change)
  } else if (aspect_type === 'delete') {
    console.log(`🗑️  Activity deleted: ${object_id}`);
    // Handle activity deletion
  }
}

async function fetchActivityDetails(user, activityId) {
  const response = await axios.get(`https://www.strava.com/api/v3/activities/${activityId}`, {
    headers: {
      Authorization: `Bearer ${user.accessToken}`
    }
  });

  return response.data;
}

function findUserByAthleteId(athleteId) {
  for (const [userId, userData] of userTokens.entries()) {
    if (userData.athleteId === athleteId) {
      return { userId, ...userData };
    }
  }
  return null;
}

// ============================================
// 3. PUSH NOTIFICATIONS (iOS)
// ============================================

/**
 * Register device token for push notifications
 * Called by iOS app after getting APNS token
 */
app.post('/api/push/register', (req, res) => {
  const { userId, deviceToken } = req.body;

  if (!userId || !deviceToken) {
    return res.status(400).json({ error: 'Missing userId or deviceToken' });
  }

  const userData = userTokens.get(userId);
  if (userData) {
    if (!userData.deviceTokens.includes(deviceToken)) {
      userData.deviceTokens.push(deviceToken);
      userTokens.set(userId, userData);
      console.log(`📱 Device token registered for user ${userId}`);
    }
  }

  res.json({ success: true });
});

async function sendPushNotification(user, notification) {
  // TODO: Implement APNS (Apple Push Notification Service)
  // For now, just log
  console.log(`📤 Would send push to user ${user.userId}:`, notification);

  /*
  Example with node-apn library:

  const apn = require('apn');
  const apnProvider = new apn.Provider({
    token: {
      key: process.env.APNS_KEY,
      keyId: process.env.APNS_KEY_ID,
      teamId: process.env.APNS_TEAM_ID
    },
    production: false
  });

  const note = new apn.Notification();
  note.alert = notification.body;
  note.topic = 'com.insightrun.app';
  note.payload = notification.data;

  for (const deviceToken of user.deviceTokens) {
    await apnProvider.send(note, deviceToken);
  }
  */
}

// ============================================
// 4. SUBSCRIPTION MANAGEMENT
// ============================================

/**
 * View current webhook subscription
 */
app.get('/api/webhooks/strava/subscription', async (req, res) => {
  try {
    const response = await axios.get('https://www.strava.com/api/v3/push_subscriptions', {
      params: {
        client_id: STRAVA_CLIENT_ID,
        client_secret: STRAVA_CLIENT_SECRET
      }
    });

    res.json(response.data);
  } catch (error) {
    console.error('Error getting subscription:', error.response?.data);
    res.status(500).json({ error: error.message });
  }
});

/**
 * Create webhook subscription
 * Call this ONCE after deploying the backend
 */
app.post('/api/webhooks/strava/subscribe', async (req, res) => {
  const callbackUrl = req.body.callbackUrl || `https://your-backend.railway.app/api/webhooks/strava`;

  try {
    const response = await axios.post('https://www.strava.com/api/v3/push_subscriptions', {
      client_id: STRAVA_CLIENT_ID,
      client_secret: STRAVA_CLIENT_SECRET,
      callback_url: callbackUrl,
      verify_token: STRAVA_WEBHOOK_VERIFY_TOKEN
    });

    console.log('✅ Webhook subscription created:', response.data);
    res.json(response.data);
  } catch (error) {
    console.error('❌ Error creating subscription:', error.response?.data);
    res.status(500).json({ error: error.response?.data || error.message });
  }
});

// ============================================
// 5. HEALTH CHECK
// ============================================

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    users: userTokens.size,
    strava: {
      clientId: STRAVA_CLIENT_ID ? 'configured' : 'missing',
      clientSecret: STRAVA_CLIENT_SECRET ? 'configured' : 'missing'
    }
  });
});

// ============================================
// START SERVER
// ============================================

app.listen(PORT, () => {
  console.log(`🚀 InsightRun Backend running on port ${PORT}`);
  console.log(`📡 Webhook URL: http://localhost:${PORT}/api/webhooks/strava`);
  console.log(`🔐 OAuth exchange URL: http://localhost:${PORT}/api/strava/exchange-token`);
  console.log('');
  console.log('To create webhook subscription:');
  console.log(`POST http://localhost:${PORT}/api/webhooks/strava/subscribe`);
  console.log(`Body: { "callbackUrl": "https://your-backend.railway.app/api/webhooks/strava" }`);
});

export default app;
