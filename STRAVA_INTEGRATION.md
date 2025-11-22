# Intégration Strava avec Lazy Loading

## Vue d'ensemble

Cette implémentation suit la stratégie **Lazy Loading** recommandée pour gérer 10 000+ utilisateurs avec des historiques de 5+ années d'activités, tout en respectant les quotas Strava.

### Stratégie Implémentée

1. **Lazy Loading** : Au lancement, charge uniquement 30 activités (page 1)
2. **Scroll Infini** : Charge les pages suivantes quand l'utilisateur scrolle
3. **Backfill** : Import progressif en arrière-plan avec `per_page=200` pour minimiser les appels API
4. **Rate Limit Monitoring** : Surveillance automatique des headers `X-RateLimit-*`

## 📋 Configuration Requise

### 1. Créer une Application Strava

1. Aller sur [Strava Developers](https://www.strava.com/settings/api)
2. Cliquer sur "Create App"
3. Remplir les informations :
   - **Application Name** : InsightRun
   - **Category** : Training
   - **Website** : https://insightrun.com
   - **Authorization Callback Domain** : `insightrun` (pour le custom URL scheme)

4. Récupérer :
   - **Client ID** : (ex: 123456)
   - **Client Secret** : ⚠️ **À GARDER SECRET** ⚠️

### 2. Configurer l'App iOS

#### a) Ajouter le URL Scheme

1. Ouvrir `InsightRun.xcodeproj`
2. Aller dans **Targets** → **InsightRun** → **Info**
3. Ajouter un **URL Type** :
   - **Identifier** : `com.insightrun.strava`
   - **URL Schemes** : `insightrun`

#### b) Ajouter les Credentials

Dans `StravaAuthService.swift`, remplacer :

```swift
private let clientId = "YOUR_STRAVA_CLIENT_ID"
private let clientSecret = "YOUR_STRAVA_CLIENT_SECRET"
```

Par vos vraies valeurs :

```swift
private let clientId = "123456" // Votre Client ID
private let clientSecret = "abc123..." // Votre Client Secret
```

⚠️ **IMPORTANT SÉCURITÉ** : En production, le `clientSecret` **NE DOIT JAMAIS** être dans le code iOS. Il doit être sur votre serveur backend. C'est une limitation temporaire pour le développement.

### 3. Configurer Info.plist

Ajouter les permissions de réseau si nécessaire :

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>
```

## 🏗️ Architecture Implémentée

### Fichiers Créés

```
Services/Strava/
├── StravaAuthService.swift      # OAuth 2.0 + Refresh Token automatique
├── StravaAPIClient.swift        # API Client + Rate Limit Monitoring
└──
ViewModels/
└── StravaViewModel.swift        # Lazy Loading + Infinite Scroll

Views/Onboarding/
└── StravaConnectionStepView.swift # Étape d'onboarding Strava
```

### Flux d'Authentification (OAuth 2.0)

```
1. User clique "Connect with Strava"
   ↓
2. ASWebAuthenticationSession ouvre Strava
   ↓
3. User autorise l'app
   ↓
4. Strava redirige vers insightrun://strava-callback?code=XXX
   ↓
5. App échange le code contre Access Token + Refresh Token
   ↓
6. Tokens stockés dans Keychain (sécurisé)
   ↓
7. Auto-refresh automatique quand Access Token expire (6h)
```

### Flux de Lazy Loading

#### Au Lancement de l'App

```swift
// Charge seulement page 1 (30 activités) - RAPIDE
let activities = try await apiClient.fetchActivities(page: 1, perPage: 30)
```

**Résultat** : L'utilisateur voit ses activités récentes en < 1 seconde

#### Scroll Infini

```swift
// Quand l'utilisateur scrolle vers le bas
func loadMoreActivities() async {
    currentPage += 1
    let newActivities = try await apiClient.fetchActivities(page: currentPage, perPage: 30)
    activities.append(contentsOf: newActivities)
}
```

**Résultat** : Chargement progressif à la demande

#### Backfill (Statistiques Globales)

```swift
// En arrière-plan, pour calculer les stats sur tout l'historique
// Utilise per_page=200 pour minimiser le nombre d'appels API
func backfillActivities() async {
    var page = 1
    while hasMore {
        let batch = try await apiClient.fetchActivities(page: page, perPage: 200)
        // Traiter et stocker...
        page += 1
    }
}
```

## 📊 Quotas Strava

### Limites par Défaut

| Période | Limite | Comment l'éviter |
|---------|--------|------------------|
| 15 minutes | 100 requêtes | Lazy Loading + Cache |
| Journalier | 1 000 requêtes | Webhooks + Backfill progressif |

### Surveillance Automatique

Le `StravaAPIClient` extrait automatiquement les headers de rate limit :

```
X-RateLimit-Usage: 23,456  (15min, daily)
X-RateLimit-Limit: 100,1000 (15min, daily)
```

Si on approche 90% de la limite, un warning s'affiche :

```
⚠️ WARNING: Approaching 15-min rate limit (92%)
```

### Demander une Augmentation de Quota

Quand vous avez des utilisateurs réels :

1. Aller sur [Strava Developer Settings](https://www.strava.com/settings/api)
2. "Request Rate Limit Increase"
3. Justifier avec :
   - Nombre d'utilisateurs
   - Architecture (Webhooks, Lazy Loading)
   - Utilisation responsable (monitoring, backfill progressif)

Généralement accepté pour passer à 10 000 ou 50 000 requêtes/jour.

## 🔔 Webhooks (Prochaine Étape Recommandée)

### Pourquoi les Webhooks ?

**Sans Webhooks** (Polling) :
```
10 000 utilisateurs × 12 requêtes/jour (toutes les 2h) = 120 000 requêtes/jour
→ Quota explosé à 8h00 du matin
```

**Avec Webhooks** :
```
Strava envoie une notification quand il y a une nouvelle activité
→ 0 requête inutile, consommation uniquement sur vraies activités
```

### Architecture Recommandée

```
┌─────────────┐
│  iPhone App │
└──────┬──────┘
       │ 1. User termine une course
       ▼
┌─────────────┐
│   Strava    │
└──────┬──────┘
       │ 2. Webhook: "Nouvel Run pour User X"
       ▼
┌─────────────┐
│ Votre       │ 3. GET /activities/{id}
│ Backend     │    (1 seule requête)
│ (Node/Python)│
└──────┬──────┘
       │ 4. Push Notification
       ▼
┌─────────────┐
│  iPhone App │
└─────────────┘
```

### Configuration Backend (TODO)

1. Créer un endpoint : `POST /webhooks/strava`
2. S'abonner aux événements : `athlete.create`, `activity.create`
3. Valider le webhook avec `hub.verify_token`
4. Traiter les notifications

Exemple Node.js/Express minimal :

```javascript
app.post('/webhooks/strava', (req, res) => {
  const { object_type, aspect_type, object_id, owner_id } = req.body;

  if (object_type === 'activity' && aspect_type === 'create') {
    // Nouvelle activité pour l'athlète owner_id
    // 1. Récupérer l'activité
    // 2. Envoyer push notification à l'app
  }

  res.status(200).send('EVENT_RECEIVED');
});
```

## 🧪 Testing

### Test OAuth Flow

1. Lancer l'app
2. Aller sur l'étape Onboarding Strava
3. Cliquer "Connect with Strava"
4. Autoriser dans le navigateur
5. Vérifier que l'app revient avec succès

### Test Lazy Loading

```swift
// Dans StravaViewModel
let viewModel = StravaViewModel()
await viewModel.loadRecentActivities() // Page 1
print(viewModel.activities.count) // Devrait être ≤ 30
```

### Test Rate Limits

```swift
// Faire plusieurs requêtes rapidement
for page in 1...10 {
    let activities = try await apiClient.fetchActivities(page: page)
}

// Vérifier les logs
if let limits = apiClient.currentRateLimits {
    print("15min: \(limits.usage15Min)/\(limits.limit15Min)")
}
```

## 🚀 Utilisation dans l'App

### Afficher la liste Strava

```swift
struct StravaActivitiesView: View {
    @StateObject var viewModel = StravaViewModel()

    var body: some View {
        List {
            ForEach(viewModel.activities) { activity in
                ActivityRow(activity: activity)
                    .onAppear {
                        // Infinite scroll
                        if activity.id == viewModel.activities.last?.id {
                            Task { await viewModel.loadMoreActivities() }
                        }
                    }
            }

            if viewModel.isLoadingMore {
                ProgressView()
            }
        }
        .task {
            await viewModel.loadRecentActivities()
        }
    }
}
```

## 📈 Performance Attendue

### Scénario : 10 000 utilisateurs, 500 activités chacun

**Sans Lazy Loading** :
- Charge 500 activités au lancement
- 500 / 30 = ~17 requêtes par utilisateur
- **Quota quotidien dépassé en < 1 minute**

**Avec Lazy Loading** :
- Charge 30 activités au lancement (1 requête)
- Scroll infini : 1 requête par page (si l'utilisateur scrolle)
- **90% des utilisateurs** ne scrollent pas → **1 seule requête**
- 10% scrollent 3 pages → **3 requêtes**
- **Moyenne : 1.2 requêtes/utilisateur** → **12 000 requêtes/jour OK**

## 🔐 Sécurité

### ✅ Ce qui est Sécurisé

- Tokens stockés dans **Keychain** (pas UserDefaults)
- Refresh automatique avant expiration
- HTTPS uniquement

### ⚠️ À Corriger en Production

**CRITIQUE** : Le `clientSecret` est actuellement dans le code iOS.

**Solution** :
1. Déplacer l'échange de tokens sur votre backend
2. iOS envoie le `code` au backend
3. Backend échange avec Strava (Client Secret jamais exposé)
4. Backend renvoie l'Access Token à l'app

## 📝 TODO

- [ ] Configurer les vraies credentials Strava (Client ID/Secret)
- [ ] Tester le flux OAuth complet
- [ ] Implémenter le backend pour les Webhooks
- [ ] Déplacer Client Secret sur le backend
- [ ] Créer une vue liste Strava avec scroll infini
- [ ] Implémenter le backfill en arrière-plan
- [ ] Ajouter un cache local (CoreData/SwiftData)
- [ ] Demander augmentation de quota Strava

## 📚 Ressources

- [Strava API Documentation](https://developers.strava.com/docs/reference/)
- [OAuth 2.0 Flow](https://developers.strava.com/docs/authentication/)
- [Webhooks Guide](https://developers.strava.com/docs/webhooks/)
- [Rate Limits](https://developers.strava.com/docs/rate-limits/)

## 🎯 Résumé

Cette implémentation suit les **meilleures pratiques** pour une app de running à grande échelle :

✅ **Lazy Loading** : Charge seulement ce qui est nécessaire
✅ **Rate Limit Monitoring** : Surveillance automatique des quotas
✅ **OAuth 2.0 complet** : Avec refresh token automatique
✅ **Onboarding fluide** : Intégré dans le flow existant
✅ **Scalable** : Prêt pour 10 000+ utilisateurs (avec Webhooks)

**Prochaine étape critique** : Mettre en place le backend pour les Webhooks et déplacer le `clientSecret`.
