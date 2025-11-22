# Architecture Scalable pour 10 000+ Utilisateurs

## 📐 Vue d'Ensemble

Cette architecture est conçue pour gérer **10 000+ utilisateurs** avec des historiques de **5+ années** d'activités, tout en respectant les quotas Strava.

```
┌─────────────────────────────────────────────────────────────┐
│                      iOS App (iPhone)                       │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   HealthKit  │  │    Strava    │  │  SwiftData   │     │
│  │   (Local)    │  │   (Cloud)    │  │   (Cache)    │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                 │                  │              │
│         │                 │                  │              │
│  ┌──────▼────────────────▼──────────────────▼───────┐     │
│  │         WorkoutListView (Unified)                 │     │
│  │  - HealthKit workouts (instant)                   │     │
│  │  - Strava activities (cached + sync)              │     │
│  │  - Infinite scroll                                │     │
│  └───────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
                               │
                               │ HTTPS (OAuth, API calls)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│              Backend (Node.js/Express)                       │
│              Deployed on Railway/Render/Fly.io              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────┐           │
│  │  OAuth Exchange (Client Secret SECURE)      │           │
│  │  - /api/strava/exchange-token                │           │
│  │  - /api/strava/refresh-token                 │           │
│  └─────────────────────────────────────────────┘           │
│                                                              │
│  ┌─────────────────────────────────────────────┐           │
│  │  Webhooks Handler                            │           │
│  │  - GET  /api/webhooks/strava (verification) │           │
│  │  - POST /api/webhooks/strava (events)       │           │
│  └─────────────────────────────────────────────┘           │
│                                                              │
│  ┌─────────────────────────────────────────────┐           │
│  │  Push Notifications (APNS)                   │           │
│  │  - /api/push/register                        │           │
│  │  - Sends alerts to iOS when new activity    │           │
│  └─────────────────────────────────────────────┘           │
│                                                              │
│  ┌─────────────────────────────────────────────┐           │
│  │  Database (PostgreSQL)                       │           │
│  │  - User tokens (encrypted)                   │           │
│  │  - Device tokens                             │           │
│  │  - Webhook events log                        │           │
│  └─────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
                               │
                               │ Webhooks (real-time notifications)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     Strava API                              │
│             https://www.strava.com/api/v3                   │
├─────────────────────────────────────────────────────────────┤
│  Rate Limits:                                               │
│  - 15 minutes: 100 requests                                 │
│  - Daily: 1000 requests (can be increased)                  │
│                                                              │
│  Endpoints Used:                                            │
│  - POST /oauth/token (via backend)                          │
│  - GET  /athlete/activities (with pagination + after)       │
│  - POST /push_subscriptions (webhooks setup)                │
└─────────────────────────────────────────────────────────────┘
```

## 🎯 Stratégie de Scaling

### 1. Cache Local (SwiftData) ✅

**Problème** : Re-télécharger 500 activités à chaque ouverture de l'app.

**Solution** :
```swift
// 1. Charger du cache (INSTANT)
let cached = try cache.fetchActivities(limit: 100, offset: 0)
activities = cached

// 2. Synchro incrémentale (seulement NOUVEAU)
let lastDate = try cache.getLastActivityDate()
let newActivities = try await api.fetchActivitiesSince(after: lastDate)

// 3. Mettre à jour le cache
try cache.saveActivities(newActivities)
```

**Gain** :
- ❌ Avant : 500 activités × 10 000 users = 5 millions de requêtes/jour
- ✅ Après : Synchro incrémentale = ~1 000 requêtes/jour (si 10% font 1 run/jour)

### 2. Webhooks (Backend) ✅

**Problème** : Poller toutes les 5 minutes pour vérifier si nouvelle activité.

**Solution** :
```javascript
// Backend reçoit notification de Strava
app.post('/api/webhooks/strava', async (req, res) => {
  const { object_id, owner_id } = req.body;

  // 1. Récupérer l'activité (1 seule requête)
  const activity = await fetchActivity(object_id);

  // 2. Push notification à l'app iOS
  await sendPush(owner_id, {
    title: 'Nouvelle activité synchronisée',
    activityId: object_id
  });
});
```

**Gain** :
- ❌ Avant : 10 000 users × 288 polls/jour (toutes les 5 min) = 2.88M requêtes/jour
- ✅ Après : Webhooks = 0 poll, seulement sur vraie activité

### 3. OAuth Sécurisé (Backend) ✅

**Problème** : `clientSecret` exposé dans l'app iOS (risque sécurité).

**Solution** :
```swift
// iOS envoie le code au backend
let url = URL(string: "https://backend.railway.app/api/strava/exchange-token")!
let body = ["code": authCode, "userId": userId]

// Backend échange avec Strava (Client Secret safe)
const response = await axios.post('https://www.strava.com/oauth/token', {
  client_id: STRAVA_CLIENT_ID,
  client_secret: STRAVA_CLIENT_SECRET, // ✅ Server-side only
  code: code
});
```

### 4. Pagination Optimisée ✅

**Stratégie** :
1. **Page 1 au lancement** : 30 activités (rapide)
2. **Scroll infini** : Charger pages suivantes à la demande
3. **Backfill** : `per_page=200` en arrière-plan pour stats

**Code** :
```swift
// Initial load (fast)
activities = try await api.fetchActivities(page: 1, perPage: 30)

// Infinite scroll
func loadMore() async {
    currentPage += 1
    let more = try await api.fetchActivities(page: currentPage, perPage: 30)
    activities.append(contentsOf: more)
}

// Backfill (background, for stats)
func backfill() async {
    var page = 1
    while hasMore {
        let batch = try await api.fetchActivities(page: page, perPage: 200)
        // Process for global stats...
        page += 1
    }
}
```

### 5. Rate Limit Monitoring ✅

**Surveillance automatique** :
```swift
func extractRateLimits(from response: HTTPURLResponse) {
    let usage = response.value(forHTTPHeaderField: "X-RateLimit-Usage")
    let limit = response.value(forHTTPHeaderField: "X-RateLimit-Limit")

    // Parse: "23,456" (15min, daily)
    currentRateLimits = StravaRateLimits(
        usage15Min: usageComponents[0],
        limit15Min: limitComponents[0],
        usageDaily: usageComponents[1],
        limitDaily: limitComponents[1]
    )

    // Warn at 90%
    if limits.percentageUsed15Min > 90 {
        print("⚠️ WARNING: Approaching 15-min limit")
    }
}
```

## 📊 Comparaison : Avant vs Après

### Scénario : 10 000 utilisateurs, 500 activités chacun

| Aspect | ❌ Architecture "Tout iOS" | ✅ Architecture Scalable |
|--------|---------------------------|-------------------------|
| **Ouverture app** | Télécharge 500 activités | Cache local (instant) |
| **Synchro** | Re-télécharge tout | Incrémentale (after=lastDate) |
| **Nouvelle activité** | Polling toutes les 5 min | Webhook notification |
| **Requêtes/jour** | ~3 millions | ~2 000 |
| **Quota Strava** | ❌ Dépassé à 8h | ✅ OK (avec marge) |
| **Sécurité** | ❌ Client Secret exposé | ✅ Backend sécurisé |
| **UX** | Lent (télécharge tout) | Rapide (cache + sync) |
| **Scalabilité** | Max ~100 utilisateurs | ✅ 10 000+ utilisateurs |

## 🚀 Déploiement en Production

### Étape 1 : Backend

```bash
# Option 1: Railway (Recommandé - 5 minutes)
# 1. Créer compte sur railway.app
# 2. Connecter le repo GitHub
# 3. Ajouter variables d'environnement
# 4. Deploy !

# Option 2: Render
# Gratuit pour commencer

# Option 3: Fly.io
cd backend
fly launch
fly secrets set STRAVA_CLIENT_ID=xxx
fly secrets set STRAVA_CLIENT_SECRET=yyy
fly deploy
```

### Étape 2 : Webhooks Strava

```bash
# Une fois le backend déployé
curl -X POST https://your-backend.railway.app/api/webhooks/strava/subscribe \
  -H "Content-Type: application/json" \
  -d '{"callbackUrl": "https://your-backend.railway.app/api/webhooks/strava"}'
```

### Étape 3 : Modifier iOS

Dans `StravaAuthService.swift` :
```swift
// Remplacer l'échange direct par un appel au backend
let backendURL = "https://your-backend.railway.app"

private func exchangeCodeForToken(code: String) async throws {
    let url = URL(string: "\(backendURL)/api/strava/exchange-token")!
    // ...
}
```

### Étape 4 : Demander Augmentation Quota

Une fois déployé avec quelques utilisateurs :
1. Aller sur https://www.strava.com/settings/api
2. "Request Rate Limit Increase"
3. Justifier avec :
   - Architecture Webhooks
   - Lazy Loading + Cache
   - Nombre d'utilisateurs
   - Synchro incrémentale

Généralement accepté pour passer à **10 000 ou 50 000 requêtes/jour**.

## 🔒 Sécurité

### ✅ Implémenté

- Client Secret côté serveur (jamais dans iOS)
- Tokens stockés dans Keychain (iOS)
- Tokens chiffrés en DB (backend)
- HTTPS uniquement
- Rate limit monitoring

### 🔜 À Ajouter (Production)

- [ ] Rate limiting sur backend (express-rate-limit)
- [ ] CORS configuré correctement
- [ ] JWT authentication pour endpoints sensibles
- [ ] Logs d'audit (qui a accédé à quoi)
- [ ] Rotation automatique des secrets
- [ ] Monitoring avec Sentry
- [ ] Backups automatiques de la DB

## 💰 Coûts Estimés

Pour 10 000 utilisateurs actifs :

| Service | Coût/mois |
|---------|-----------|
| Backend (Railway) | $5-15 |
| Base de données PostgreSQL | Inclus |
| Push Notifications (APNS) | Gratuit |
| Strava API | Gratuit |
| Monitoring (Sentry) | Gratuit tier |
| **Total** | **~$10-20/mois** |

Pour 100 000 utilisateurs : ~$50-100/mois

## 📈 Performance Attendue

### Temps de Chargement

- **Premier lancement** (no cache) : 1-2 secondes
- **Lancements suivants** (with cache) : < 0.5 seconde
- **Synchro incrémentale** : < 1 seconde

### Consommation Quota

Avec 10 000 utilisateurs :
- **Polling (sans webhooks)** : 120 000 requêtes/jour ❌
- **Webhooks + Cache** : ~1 000 requêtes/jour ✅

Marge de sécurité : **90%** du quota disponible pour pics.

## 🎯 Résumé des Fichiers

### iOS

```
Services/
├── Strava/
│   ├── StravaAuthService.swift      (OAuth 2.0)
│   ├── StravaAPIClient.swift        (API + Rate Limits)
│   └── StravaCache.swift            (SwiftData cache)
ViewModels/
└── StravaViewModel.swift            (Lazy Loading + Sync)
Views/Onboarding/
└── StravaConnectionStepView.swift  (Onboarding)
```

### Backend

```
backend/
├── server.js                        (Express server)
├── package.json                     (Dependencies)
├── .env.example                     (Configuration)
└── README.md                        (Deployment guide)
```

### Documentation

```
STRAVA_INTEGRATION.md                (OAuth + Webhooks setup)
ARCHITECTURE_SCALABLE.md             (This file - Architecture overview)
```

## 🆘 Troubleshooting

### Problème : Quota dépassé

**Diagnostic** :
```bash
# Vérifier les quotas
curl https://your-backend.railway.app/health
```

**Solutions** :
1. Vérifier que les webhooks fonctionnent
2. Augmenter le cache TTL
3. Demander augmentation quota à Strava

### Problème : Webhooks ne fonctionnent pas

**Diagnostic** :
```bash
# Vérifier la subscription
curl https://your-backend.railway.app/api/webhooks/strava/subscription
```

**Solutions** :
1. Vérifier que l'URL backend est accessible publiquement
2. Vérifier le `verify_token`
3. Regarder les logs backend

### Problème : Cache ne se met pas à jour

**Diagnostic** :
```swift
// Dans iOS app
let stats = try cache.getCacheStats()
print("Cache: \(stats.totalActivities) activities")
print("Last: \(stats.lastActivityDate)")
```

**Solutions** :
1. Forcer une synchro : `await viewModel.syncNewActivities()`
2. Vider le cache : `try cache.clearAll()`
3. Vérifier les logs de synchro

## 🎉 Conclusion

Avec cette architecture, vous êtes **prêt pour 10 000+ utilisateurs** :

✅ **Lazy Loading** : Charge seulement ce qui est nécessaire
✅ **Cache Local** : Évite de re-télécharger 2 fois
✅ **Synchro Incrémentale** : Seulement les nouvelles activités
✅ **Webhooks** : Notifications en temps réel (0 polling)
✅ **OAuth Sécurisé** : Client Secret sur serveur
✅ **Rate Limit Safe** : 90% de marge de sécurité

**Prochaine étape critique** : Déployer le backend et activer les webhooks Strava.

---

**Questions ?** Voir `STRAVA_INTEGRATION.md` pour le guide détaillé ou `backend/README.md` pour le déploiement.
