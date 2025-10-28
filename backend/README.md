# InsightRun Backend API

Backend sécurisé pour l'application iOS InsightRun. Proxifie les requêtes vers OpenRouter API avec rate limiting et authentification.

## 🚀 Stack Technique

- **Runtime:** Cloudflare Workers (Edge computing global)
- **Framework:** Hono (ultra-rapide, 3.5KB)
- **Package Manager:** Bun
- **Rate Limiting:** Cloudflare KV (Key-Value store)

## ✨ Fonctionnalités

- ✅ Proxy sécurisé vers OpenRouter API
- ✅ Rate limiting (100 requêtes/heure par IP)
- ✅ Authentification par clé app
- ✅ Support streaming (SSE)
- ✅ CORS configuré
- ✅ Logging et monitoring
- ✅ Gratuit jusqu'à 100k requêtes/jour

## 📦 Installation

```bash
# Installer les dépendances
bun install

# Se connecter à Cloudflare
bunx wrangler login

# Créer le KV namespace pour rate limiting
bunx wrangler kv:namespace create RATE_LIMITER
bunx wrangler kv:namespace create RATE_LIMITER --preview

# Copier les IDs retournés dans wrangler.toml
```

## 🔐 Configuration des Secrets

```bash
# Production
bunx wrangler secret put OPENROUTER_API_KEY
# Entrer: sk-or-v1-VOTRE_CLE_OPENROUTER

bunx wrangler secret put APP_SECRET
# Entrer: insightrun-ios-v1-SECRET_UNIQUE
```

## 🧪 Développement Local

```bash
# Lancer en local (utilise .dev.vars)
bun run dev

# Tester l'API
curl http://localhost:8787/health
```

## 🚢 Déploiement

```bash
# Déployer en production
bun run deploy

# Voir les logs en temps réel
bun run tail
```

## 📡 Endpoints

### GET `/`
Health check basique.

**Response:**
```json
{
  "status": "ok",
  "service": "InsightRun Backend API",
  "version": "1.0.0",
  "timestamp": "2025-10-21T12:00:00.000Z"
}
```

### POST `/api/chat`
Envoyer une question à l'IA.

**Headers:**
```
X-App-Key: insightrun-ios-v1-SECRET_UNIQUE
Content-Type: application/json
```

**Request:**
```json
{
  "prompt": "Comment améliorer mon allure ?",
  "systemPrompt": "Tu es un coach de running...",
  "model": "anthropic/claude-sonnet-4.5"
}
```

**Response:**
```json
{
  "response": "Pour améliorer votre allure...",
  "model": "anthropic/claude-sonnet-4.5",
  "usage": {
    "prompt_tokens": 45,
    "completion_tokens": 120,
    "total_tokens": 165
  },
  "timestamp": "2025-10-21T12:00:00.000Z"
}
```

### POST `/api/chat/stream`
Version streaming (SSE).

**Response:** Server-Sent Events (text/event-stream)

### GET `/api/stats`
Vérifier les quotas rate limiting.

**Response:**
```json
{
  "requestsRemaining": 95,
  "limit": 100,
  "resetIn": 3600,
  "ip": "192.168.1.1"
}
```

## 🔒 Sécurité

1. **Clé API OpenRouter** : Stockée en secret Cloudflare (jamais dans le code)
2. **Authentification app** : Clé `X-App-Key` requise
3. **Rate Limiting** : 100 requêtes/heure par IP
4. **Validation** : Longueur max du prompt (2000 chars)
5. **CORS** : Configuré pour limiter les origins

## 💰 Coûts

**Cloudflare Workers (Free Tier) :**
- ✅ 100,000 requêtes/jour gratuites
- ✅ 10ms CPU time par requête gratuit
- ✅ KV : 100,000 lectures/jour gratuites

**OpenRouter API :**
- Claude Sonnet 4.5 : ~0.003$/1K tokens input, ~0.015$/1K tokens output
- Voir [OpenRouter Pricing](https://openrouter.ai/docs#models)

**Estimation pour 100 utilisateurs actifs/mois :**
- ~50€/an si bien optimisé

## 📊 Monitoring

```bash
# Voir les logs en temps réel
bunx wrangler tail

# Voir les métriques dans dashboard Cloudflare
# https://dash.cloudflare.com
```

## 🔧 Troubleshooting

**Erreur 401 Unauthorized:**
- Vérifier que la clé `X-App-Key` est correcte
- Vérifier que `APP_SECRET` est bien configuré

**Erreur 429 Rate Limit:**
- Trop de requêtes en 1h
- Attendre 1h ou augmenter la limite dans le code

**Erreur 500 AI Service:**
- Vérifier que `OPENROUTER_API_KEY` est valide
- Vérifier les logs avec `bun run tail`

## 🚀 Prochaines Étapes

- [ ] Ajouter authentification utilisateur (Firebase Auth)
- [ ] Implémenter budget limiting quotidien
- [ ] Ajouter analytics détaillées
- [ ] Support multi-modèles IA
- [ ] Cache des réponses fréquentes
- [ ] Webhooks pour notifications

## 📝 License

MIT
