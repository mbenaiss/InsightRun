# InsightRun Backend - Strava Integration

Backend sécurisé pour gérer OAuth et Webhooks Strava pour 10 000+ utilisateurs.

## 🎯 Pourquoi ce Backend ?

**Sans backend** (tout dans l'iPhone) :
- ❌ Client Secret exposé dans l'app (risque de sécurité)
- ❌ 10 000 utilisateurs × polling toutes les 5 min = quotas explosés
- ❌ Impossible de scaler

**Avec ce backend** :
- ✅ Client Secret sécurisé côté serveur
- ✅ Webhooks : Strava vous prévient au lieu de poller
- ✅ 0 requête inutile = quotas économisés
- ✅ Prêt pour 10 000+ utilisateurs

## 📋 Fonctionnalités

1. **OAuth sécurisé** : Échange de tokens côté serveur
2. **Webhooks Strava** : Notifications en temps réel
3. **Push Notifications iOS** : Alerte l'app quand nouvelle activité
4. **Rate limit safe** : Consomme uniquement sur vraies activités

## 🚀 Déploiement Rapide

### Option 1: Railway (Recommandé - 5 minutes)

1. Créer un compte sur [Railway.app](https://railway.app)
2. Créer un nouveau projet
3. Connecter ce repo GitHub
4. Ajouter les variables d'environnement :
   ```
   STRAVA_CLIENT_ID=123456
   STRAVA_CLIENT_SECRET=abc123...
   STRAVA_WEBHOOK_VERIFY_TOKEN=un_token_aleatoire
   ```
5. Déployer !

Railway vous donnera une URL : `https://insightrun-backend-production.up.railway.app`

### Option 2: Render.com (Gratuit)

1. Créer un compte sur [Render.com](https://render.com)
2. New Web Service → Connect ce repo
3. Build Command: `npm install`
4. Start Command: `npm start`
5. Ajouter les env vars
6. Deploy

### Option 3: Fly.io

```bash
# Installer Fly CLI
brew install flyctl  # macOS
# ou: curl -L https://fly.io/install.sh | sh

# Login
fly auth login

# Créer l'app
cd backend
fly launch

# Définir les secrets
fly secrets set STRAVA_CLIENT_ID=123456
fly secrets set STRAVA_CLIENT_SECRET=abc123...
fly secrets set STRAVA_WEBHOOK_VERIFY_TOKEN=random_string

# Déployer
fly deploy
```

## ⚙️ Configuration

### 1. Variables d'Environnement

Copier `.env.example` vers `.env` :

```bash
cp .env.example .env
```

Puis remplir avec vos vraies valeurs :

```env
STRAVA_CLIENT_ID=123456
STRAVA_CLIENT_SECRET=abc123def456...
STRAVA_WEBHOOK_VERIFY_TOKEN=INSIGHTRUN_SECRET_2024
PORT=3000
```

### 2. Activer les Webhooks Strava

Une fois le backend déployé, créer une souscription webhook directement via l'API Strava :

```bash
# Créer une souscription webhook Strava
curl -X POST https://www.strava.com/api/v3/push_subscriptions \
  -F client_id=YOUR_STRAVA_CLIENT_ID \
  -F client_secret=YOUR_STRAVA_CLIENT_SECRET \
  -F callback_url=https://api.insightrun.altcode.studio/api/strava/webhooks/callback \
  -F verify_token=YOUR_VERIFY_TOKEN
```

Réponse attendue :
```json
{
  "id": 123456,
  "resource_state": 2,
  "application_id": 789,
  "callback_url": "https://api.insightrun.altcode.studio/api/strava/webhooks/callback",
  "created_at": "2024-01-15T10:00:00Z",
  "updated_at": "2024-01-15T10:00:00Z"
}
```

### 3. Vérifier le Webhook

```bash
# Lister les souscriptions webhook actives
curl -G https://www.strava.com/api/v3/push_subscriptions \
  -d client_id=YOUR_STRAVA_CLIENT_ID \
  -d client_secret=YOUR_STRAVA_CLIENT_SECRET
```

## 🧪 Test en Local

```bash
# Installer les dépendances
bun install

# Appliquer les migrations de base de données (local)
bun run db:migrate:local

# Lancer le serveur
bun run dev

# Tester l'échange de token
curl -X POST http://localhost:8787/api/strava/exchange-token \
  -H "Content-Type: application/json" \
  -H "X-App-Key: healthapp-LEtZ5vhVA5RBpw8u-F0Rxvk1mHagGeINJEI9GOPUFs4" \
  -d '{
    "code": "authorization_code_from_oauth",
    "userId": "user123"
  }'
```

## 🗄️ Database Migrations

Le backend utilise **Cloudflare D1** (SQLite) pour le cache des activités Strava. Les migrations sont gérées nativement par **Wrangler**.

### Commandes Disponibles

```bash
# Lister les migrations (appliquées et en attente)
bun run db:migrate:list

# Appliquer les migrations en LOCAL (dev)
bun run db:migrate:local

# Appliquer les migrations en PRODUCTION
bun run db:migrate:remote

# Créer une nouvelle migration
bun run db:migrate:create "Nom de la migration"
```

### Workflow

1. **Création d'une migration** :
   ```bash
   bun run db:migrate:create "Add user preferences table"
   # Crée: migrations/000X_Add_user_preferences_table.sql
   ```

2. **Éditer le fichier SQL généré** :
   ```sql
   -- Migration number: 000X
   CREATE TABLE user_preferences (
     user_id TEXT PRIMARY KEY,
     theme TEXT DEFAULT 'light',
     notifications_enabled BOOLEAN DEFAULT 1
   );
   ```

3. **Tester en local** :
   ```bash
   bun run db:migrate:local
   ```

4. **Déployer en production** :
   ```bash
   bun run deploy
   # Les migrations sont automatiquement appliquées avant le déploiement !
   ```

### Structure

```
backend/
├── migrations/                                    # Migrations D1 (Wrangler natif)
│   └── 0001_Initial_schema_-_Strava_activities_cache.sql
├── wrangler.toml                                 # Config Cloudflare Workers + D1
└── src/
    ├── services/stravaCache.ts                   # Utilise D1
    └── routes/strava.ts                          # Endpoints utilisant le cache
```

### Tester les Webhooks localement avec ngrok

Strava a besoin d'une URL publique HTTPS pour les webhooks. En local, utilisez ngrok :

```bash
# Installer ngrok
brew install ngrok  # macOS

# Exposer votre serveur local (Cloudflare Workers tourne sur port 8787)
ngrok http 8787
```

ngrok vous donnera une URL : `https://abc123.ngrok.io`

Utilisez cette URL pour créer la souscription directement via l'API Strava :

```bash
# Créer une souscription webhook avec l'URL ngrok
curl -X POST https://www.strava.com/api/v3/push_subscriptions \
  -F client_id=YOUR_STRAVA_CLIENT_ID \
  -F client_secret=YOUR_STRAVA_CLIENT_SECRET \
  -F callback_url=https://abc123.ngrok.io/api/strava/webhooks/callback \
  -F verify_token=YOUR_VERIFY_TOKEN
```

## 📱 Intégration iOS

Modifier `StravaAuthService.swift` pour utiliser le backend :

```swift
// Avant (INSECURE - Client Secret dans l'app)
private func exchangeCodeForToken(code: String) async throws {
    let url = URL(string: "https://www.strava.com/oauth/token")!
    // ...
}

// Après (SECURE - via backend)
private func exchangeCodeForToken(code: String) async throws {
    let url = URL(string: "https://your-backend.railway.app/api/strava/exchange-token")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
        "code": code,
        "userId": UserIdentityService.shared.userID
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)

    // Traiter la réponse...
}
```

## 🔔 Push Notifications (Optionnel mais Recommandé)

Pour envoyer des push à l'app iOS quand nouvelle activité :

1. Créer une APNs Key dans Apple Developer Portal
2. Télécharger le fichier `.p8`
3. Ajouter les env vars :
   ```
   APNS_KEY_ID=ABC123XYZ
   APNS_TEAM_ID=DEF456
   ```
4. Installer `node-apn` :
   ```bash
   npm install apn
   ```

L'iOS doit enregistrer son device token :

```swift
// Dans iOS app
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

    // Envoyer au backend
    Task {
        let url = URL(string: "https://your-backend.railway.app/api/push/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "userId": UserIdentityService.shared.userID,
            "deviceToken": token
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
    }
}
```

## 📊 Base de Données (Production)

Pour production, remplacer `Map` par une vraie DB (PostgreSQL recommandé) :

```javascript
// Exemple avec PostgreSQL
import pg from 'pg';
const { Pool } = pg;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

// Stocker les tokens
async function saveUserTokens(userId, tokens) {
  await pool.query(
    'INSERT INTO user_tokens (user_id, access_token, refresh_token, expires_at, athlete_id) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (user_id) DO UPDATE SET access_token = $2, refresh_token = $3, expires_at = $4',
    [userId, tokens.accessToken, tokens.refreshToken, tokens.expiresAt, tokens.athleteId]
  );
}
```

## 🚨 Monitoring

Une fois en production, monitorer :

1. **Logs** : Railway/Render fournissent des logs en temps réel
2. **Uptime** : Utiliser [UptimeRobot](https://uptimerobot.com) (gratuit)
3. **Erreurs** : Sentry ou Bugsnag pour tracker les erreurs

## 📈 Quotas Strava avec Webhooks

**Sans Webhooks** :
- 10 000 utilisateurs × 12 requêtes/jour (polling toutes les 2h) = **120 000 requêtes/jour**
- Quota par défaut = 1 000 requêtes/jour
- ❌ **Quota dépassé à 8h du matin**

**Avec Webhooks** :
- Strava envoie notification → backend fait 1 requête
- Si 10% des utilisateurs font 1 run/jour = 1 000 runs = **1 000 requêtes/jour**
- ✅ **Dans les quotas !**

## 🔐 Sécurité

✅ **Implémenté** :
- Client Secret côté serveur (jamais exposé à l'iOS)
- HTTPS uniquement
- Tokens stockés chiffrés (en prod avec DB)

⚠️ **À ajouter** :
- Rate limiting (express-rate-limit)
- CORS configuré correctement
- Authentication pour les endpoints (JWT)
- Logs d'audit

## 📚 Endpoints API

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| POST | `/api/strava/exchange-token` | Échange code OAuth contre tokens |
| POST | `/api/strava/refresh-token` | Rafraîchit l'access token |
| GET | `/api/strava/activities` | Liste des activités (avec pagination) |
| POST | `/api/strava/sync` | Synchronise toutes les activités |
| GET | `/api/strava/webhooks/callback` | Vérification webhook Strava |
| POST | `/api/strava/webhooks/callback` | Réception événements Strava |
| GET | `/health` | Health check |

## 🎯 Prochaines Étapes

- [ ] Déployer sur Railway/Render/Fly.io
- [ ] Configurer les variables d'environnement
- [ ] Activer le webhook Strava
- [ ] Modifier l'iOS pour utiliser le backend
- [ ] Demander augmentation de quota Strava
- [ ] Ajouter une DB PostgreSQL
- [ ] Implémenter les push notifications
- [ ] Monitoring avec Sentry

## 💰 Coûts

- **Railway** : Gratuit pour commencer, puis $5/mois
- **Render** : Gratuit (avec quelques limitations)
- **Fly.io** : Gratuit pour petit usage
- **PostgreSQL** : Gratuit (Railway/Render inclus)

Pour 10 000 utilisateurs actifs : ~$20-30/mois

## 🆘 Support

Si problème :
1. Vérifier les logs du backend
2. Tester avec `curl` d'abord
3. Vérifier que le webhook est bien créé
4. Vérifier les variables d'environnement

---

**Architecture complète** : iOS App ↔️ Backend ↔️ Strava API ↔️ Webhooks

Avec cette archi, vous êtes **prêt pour 100 000 utilisateurs** 🚀
