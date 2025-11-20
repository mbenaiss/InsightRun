# API Model Routing Documentation

## Overview

L'API InsightRun utilise un système de **routing sémantique** pour sélectionner automatiquement le meilleur modèle d'IA en fonction du type de requête. Au lieu d'envoyer un nom de modèle spécifique (ex: `anthropic/claude-haiku-4.5`), vous envoyez un **type de requête sémantique** (ex: `MODERATE`, `COMPLEX`) et le backend choisit le modèle optimal.

## Avantages

✅ **Flexibilité** - Changer de modèle sans mettre à jour l'app iOS
✅ **Optimisation des coûts** - Le backend gère les quotas et sélectionne le modèle le plus économique
✅ **A/B Testing** - Tester différents modèles facilement
✅ **Abstraction** - L'iOS n'a pas besoin de connaître les modèles spécifiques

## Types de Requêtes (`RequestType`)

### Requêtes Générales

| Type | Modèle par défaut | Description | Cas d'usage |
|------|------------------|-------------|-------------|
| `SIMPLE` | Grok 4 Fast | Requêtes basiques, statistiques | "Quelle était ma vitesse ?" |
| `MODERATE` | Claude Haiku 4.5 | Analyse et conseils personnalisés | Plans d'entraînement, analyse de performance |
| `COMPLEX` | Claude Sonnet 4.5* | Analyse médicale, risques de blessure | HRV, asymétrie, risques physiologiques |

*Avec quota mensuel (10 requêtes/utilisateur/mois). Fallback vers Haiku si quota dépassé.

### Requêtes Spécialisées

| Type | Modèle par défaut | Description |
|------|------------------|-------------|
| `WORKOUT_GENERATION` | Gemini 2.5 Flash Lite | Génération de plans d'entraînement structurés (JSON) |
| `BATCH_PROCESSING` | Gemini 2.5 Flash Lite | Analyse par lots d'historique (50 workouts) |
| `SMART_SUGGESTION` | Grok 4 Fast | Suggestions intelligentes d'entraînement |
| `CLASSIFICATION` | Grok 4 Fast | Classification de complexité de prompt (usage interne) |

## Gestion des Quotas

### Quota Sonnet (Contrôle des Coûts)

**Configuration:**
- Limite: **10 requêtes/utilisateur/mois**
- Stockage: Cloudflare KV
- Reset: 1er jour du mois
- Fallback: Claude Haiku 4.5 si quota dépassé

**Coûts estimés par utilisateur:**
- Simple (Grok): ~$0.01/mois
- Moderate (Haiku): ~$0.15/mois
- Complex (Sonnet): ~$0.35/mois
- Workout Gen (Gemini): ~$0.02/mois
- **Total: ~$0.53/utilisateur/mois** (89% de marge @ $4.99/mois)

### Rate Limiting Global

- **Par IP**: 100 requêtes/heure
- **Par Utilisateur**: 1000 requêtes/mois

## Utilisation de l'API

### Option 1: requestType (Recommandé)

Envoyez `requestType` et laissez le backend choisir le meilleur modèle.

```typescript
// POST /api/chat/v2
{
  "promptType": "workout_coach",
  "requestType": "MODERATE", // ← Sémantique
  "userQuestion": "Comment améliorer ma VMA?",
  "language": "fr",
  "data": {
    "workout": { ... },
    "recentWorkouts": { ... }
  }
}
```

**Réponse:**
- Le backend sélectionne Claude Haiku 4.5
- Vérifie les quotas
- Stream la réponse
- Incrémente les compteurs

### Option 2: model (Backward Compatibility)

Vous pouvez toujours spécifier un modèle spécifique si nécessaire.

```typescript
{
  "promptType": "workout_coach",
  "model": "anthropic/claude-sonnet-4.5", // ← Modèle direct
  "userQuestion": "Analyse mon risque de blessure",
  "language": "fr",
  "data": { ... }
}
```

⚠️ **Attention:** Le système de quotas Sonnet ne s'applique PAS si vous utilisez `model` directement.

### Option 3: Classification Automatique (Futur)

Si ni `requestType` ni `model` n'est fourni, le backend peut classifier automatiquement la complexité.

```typescript
{
  "promptType": "workout_coach",
  // Pas de requestType ni model
  "userQuestion": "Quelle était ma vitesse moyenne?",
  "language": "fr",
  "data": { ... }
}
```

→ Le backend utilise Grok pour classifier la question comme `SIMPLE` et route vers Grok 4 Fast.

## Endpoints Supportés

### `/api/chat/v2` - Chat avec contexte

**Paramètres:**
- `promptType`: "workout_coach"
- `requestType?`: SIMPLE | MODERATE | COMPLEX
- `model?`: Nom du modèle (fallback)
- `userQuestion`: Question de l'utilisateur
- `language`: Code langue (fr, en, es, etc.)
- `data`: Données contextuelles (workout, recovery, etc.)

**Streaming:** Oui (SSE)

### `/api/analyze-history/batch` - Analyse par lots

**Paramètres:**
- `workouts`: Array de WorkoutData (max 50)
- `batchIndex`: Numéro du batch
- `language`: Code langue
- `requestType?`: BATCH_PROCESSING (recommandé)
- `model?`: Fallback

**Streaming:** Non

### `/api/analyze-history/consolidate` - Consolidation

**Paramètres:**
- `batchSummaries`: Array de résumés
- `totalWorkouts`: Nombre total de workouts
- `profile?`: Profil santé
- `language`: Code langue
- `requestType?`: MODERATE (recommandé)
- `model?`: Fallback

**Streaming:** Non

### `/api/generate-workout` - Génération de workout

**Paramètres:**
- `userQuestion`: Description du workout souhaité
- `language`: Code langue
- `userContext?`: Contexte utilisateur
- `requestType?`: WORKOUT_GENERATION (recommandé)
- `model?`: Fallback

**Streaming:** Non (retourne JSON structuré)

### `/api/workout/smart-suggestion` - Suggestion intelligente

**Paramètres:**
- Utilise le format ChatRequestV2
- `requestType?`: SMART_SUGGESTION (recommandé)
- `model?`: Fallback

**Streaming:** Non

## Mapping des Modèles

Voici comment chaque `requestType` est mappé à un modèle:

```typescript
SIMPLE              → Grok 4 Fast ($0.40/1M tokens)
MODERATE            → Claude Haiku 4.5 ($15/1M tokens)
COMPLEX             → Claude Sonnet 4.5 ($34.6/1M tokens) avec quota
WORKOUT_GENERATION  → Gemini 2.5 Flash Lite ($1.50/1M tokens)
BATCH_PROCESSING    → Gemini 2.5 Flash Lite ($1.50/1M tokens)
SMART_SUGGESTION    → Grok 4 Fast ($0.40/1M tokens)
CLASSIFICATION      → Grok 4 Fast ($0.40/1M tokens)
```

## Monitoring et Analytics

### Headers de Réponse

Toutes les réponses incluent des headers de quota:

```http
X-RateLimit-IP-Limit: 100
X-RateLimit-IP-Remaining: 95
X-RateLimit-IP-Reset: 1704067200
X-RateLimit-User-Limit: 1000
X-RateLimit-User-Remaining: 985
X-RateLimit-User-Reset: 1706745600
```

### Endpoint Stats

```bash
GET /api/stats
Headers:
  X-User-ID: <userId>
```

**Réponse:**
```json
{
  "identifier": "user-123",
  "quotas": {
    "ip": {
      "limit": 100,
      "remaining": 95,
      "resetAt": 1704067200,
      "resetIn": 3420
    },
    "user": {
      "limit": 1000,
      "remaining": 985,
      "resetAt": 1706745600,
      "resetIn": 2592000
    }
  },
  "allowed": true
}
```

## Gestion des Erreurs

### Quota Dépassé

**Status:** 429 Too Many Requests

```json
{
  "error": "Quota exceeded",
  "message": "User quota exceeded. Resets in 2592000 seconds.",
  "restrictedBy": "user",
  "quotas": {
    "user": {
      "limit": 1000,
      "remaining": 0,
      "resetAt": 1706745600
    }
  }
}
```

### RequestType Invalide

**Status:** 400 Bad Request

```json
{
  "error": "Bad Request",
  "message": "Invalid requestType. Valid values: SIMPLE, MODERATE, COMPLEX, WORKOUT_GENERATION, BATCH_PROCESSING, SMART_SUGGESTION, CLASSIFICATION"
}
```

## Migration depuis l'Ancien Système

### Avant (avec model)

```typescript
const payload = {
  promptType: 'workout_coach',
  model: 'anthropic/claude-haiku-4.5', // ❌ Modèle spécifique
  userQuestion: 'Comment améliorer mon endurance?',
  language: 'fr',
  data: { ... }
}
```

### Après (avec requestType)

```typescript
const payload = {
  promptType: 'workout_coach',
  requestType: 'MODERATE', // ✅ Type sémantique
  userQuestion: 'Comment améliorer mon endurance?',
  language: 'fr',
  data: { ... }
}
```

### Compatibilité Rétroactive

Les deux approches fonctionnent ! Si vous envoyez les deux, `requestType` a priorité:

```typescript
{
  requestType: 'SIMPLE',     // ← Utilisé
  model: 'claude-sonnet',    // ← Ignoré
  ...
}
```

## Exemples Complets

### Exemple 1: Question Simple

```typescript
POST /api/chat/v2
{
  "promptType": "workout_coach",
  "requestType": "SIMPLE",
  "userQuestion": "Quelle distance ai-je couru aujourd'hui?",
  "language": "fr",
  "data": {
    "workout": {
      "date": "2025-01-20",
      "distance": 5000,
      "duration": 1800
    }
  }
}
```

→ Utilise **Grok 4 Fast** (~$0.0004)

### Exemple 2: Analyse Modérée

```typescript
POST /api/chat/v2
{
  "promptType": "workout_coach",
  "requestType": "MODERATE",
  "userQuestion": "Analyse mes progrès du mois",
  "language": "fr",
  "data": {
    "recentWorkouts": {
      "workouts": [...],
      "totalDistance": 100000,
      "avgPace": 5.5
    }
  }
}
```

→ Utilise **Claude Haiku 4.5** (~$0.015)

### Exemple 3: Analyse Complexe

```typescript
POST /api/chat/v2
{
  "promptType": "workout_coach",
  "requestType": "COMPLEX",
  "userQuestion": "Analyse mon risque de blessure basé sur mon HRV",
  "language": "fr",
  "data": {
    "recovery": {
      "hrv": 45,
      "restingHeartRate": 72
    },
    "recentWorkouts": { ... }
  }
}
```

→ Utilise **Claude Sonnet 4.5** (~$0.035) si quota disponible, sinon **Haiku**

### Exemple 4: Génération de Workout

```typescript
POST /api/generate-workout
{
  "userQuestion": "Crée-moi un entraînement fractionné 10x400m",
  "language": "fr",
  "requestType": "WORKOUT_GENERATION",
  "userContext": {
    "avgPace": 5.5,
    "fitnessLevel": "intermediate"
  }
}
```

→ Utilise **Gemini 2.5 Flash Lite** (~$0.002)

## Logs Backend

Le backend log chaque sélection de modèle pour faciliter le debugging:

```
🎯 Using requestType: MODERATE
✅ Selected model: Claude Haiku 4.5 (anthropic/claude-haiku-4.5)
💰 ModelRouter: Sonnet usage for user-123: 3/10 this month
```

---

**Dernière mise à jour:** 2025-01-20
**Version API:** 2.0
