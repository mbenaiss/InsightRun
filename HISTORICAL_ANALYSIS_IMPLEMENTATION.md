# Historical Analysis - One-Time Deep Analysis Strategy

## ✅ Implémentation Complétée

Cette fonctionnalité implémente la stratégie "One-Time Deep Analysis" pour optimiser le contexte IA et réduire les coûts.

## 📁 Fichiers Créés

### Backend
- `backend/src/types.ts` - Ajout des types `HistoricalAnalysisRequest` et `HistoricalAnalysisResponse`
- `backend/src/prompts.ts` - Ajout de `buildHistoricalAnalysisPrompt()` et support du résumé historique dans `buildWorkoutCoachPrompt()`
- `backend/src/index.ts` - Ajout de l'endpoint `/api/analyze-history`

### iOS
- `InsightRun/insightrun/Models/HistoricalSummary.swift` - Modèle pour le résumé historique
- `InsightRun/insightrun/Services/HistoricalSummaryStorage.swift` - Service de stockage persistant
- `InsightRun/insightrun/Services/BackendModels.swift` - Ajout des types pour l'analyse historique
- `InsightRun/insightrun/Services/BackendAPIClient.swift` - Ajout de `generateHistoricalSummary()`
- `InsightRun/insightrun/Services/WorkoutAIService.swift` - Intégration du résumé historique dans les requêtes
- `InsightRun/insightrun/Views/HistoricalAnalysisOnboardingView.swift` - Vue d'onboarding avec progress bar

## 🔧 Modifications Apportées

### Backend

1. **Endpoint `/api/analyze-history`**
   - Accepte un tableau de workouts + model + language
   - Génère un résumé historique complet (~1500-2000 tokens)
   - Retourne le résumé avec metadata

2. **Prompt d'analyse historique**
   - Analyse complète des 365 derniers workouts
   - Génère 6 sections : Tendances, Patterns, Profil physiologique, Milestones, Warnings, Baseline metrics

3. **Intégration dans le contexte quotidien**
   - Le résumé historique est ajouté en premier dans le system prompt
   - Suivi des workouts récents (derniers 14 jours)

### iOS

1. **Stockage local**
   - Utilise `UserDefaults` avec encodage JSON
   - Détecte automatiquement si le résumé doit être rafraîchi (>3 mois)

2. **Onboarding View**
   - Progress bar animée
   - Récupère tous les workouts depuis HealthKit
   - Envoie au backend pour analyse
   - Sauvegarde localement

3. **Intégration transparente**
   - `WorkoutAIService` charge automatiquement le résumé historique
   - Aucun changement nécessaire dans les vues existantes

## 🚀 Comment Intégrer dans l'App

### Étape 1: Afficher l'Onboarding

Ajoutez cette vue à votre flow d'onboarding initial ou dans les settings:

```swift
import SwiftUI

struct ContentView: View {
    @State private var showHistoricalAnalysis = false

    var body: some View {
        VStack {
            // Votre contenu existant

            Button("Generate Athletic Profile") {
                showHistoricalAnalysis = true
            }
        }
        .sheet(isPresented: $showHistoricalAnalysis) {
            HistoricalAnalysisOnboardingView()
        }
    }
}
```

### Étape 2: Détection Premier Lancement

Ajoutez la détection automatique au premier lancement:

```swift
struct InsightRunApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    checkFirstLaunch()
                }
        }
    }

    private func checkFirstLaunch() {
        // Check if historical summary needs generation
        if HistoricalSummaryStorage.shared.needsGeneration() {
            // Show onboarding
            appState.showHistoricalAnalysisOnboarding = true
        }
    }
}
```

### Étape 3: Bouton de Régénération (Settings)

Ajoutez un bouton dans les settings pour régénérer le profil:

```swift
struct SettingsView: View {
    @State private var showRegenerateSheet = false

    var body: some View {
        List {
            Section("Athletic Profile") {
                if let summary = HistoricalSummaryStorage.shared.load() {
                    VStack(alignment: .leading) {
                        Text("Generated: \(summary.generatedDateFormatted)")
                        Text("\(summary.workoutCount) workouts analyzed")
                        Text("Date range: \(summary.dateRangeFormatted)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Button("Regenerate Profile") {
                        showRegenerateSheet = true
                    }
                } else {
                    Button("Generate Athletic Profile") {
                        showRegenerateSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showRegenerateSheet) {
            HistoricalAnalysisOnboardingView()
        }
    }
}
```

## 🧪 Comment Tester

### Test 1: Génération du Profil

1. Lancez l'app
2. Ouvrez `HistoricalAnalysisOnboardingView`
3. Appuyez sur "Analyze My Training History"
4. Vérifiez que:
   - La progress bar avance
   - Les messages de statut changent
   - L'analyse se termine avec succès (100%)
   - La vue se ferme automatiquement

**Logs attendus:**
```
📊 HistoricalAnalysis: Found 142 workouts
📊 HistoricalAnalysis: Converted 142 workouts to API format
📊 BackendAPIClient: Requesting historical analysis for 142 workouts...
✅ BackendAPIClient: Historical analysis completed (142 workouts)
✅ HistoricalAnalysis: Onboarding complete
```

### Test 2: Vérifier le Stockage

```swift
// Dans un test ou debug view
let storage = HistoricalSummaryStorage.shared

if let summary = storage.load() {
    print("✅ Summary loaded")
    print("   Workouts: \(summary.workoutCount)")
    print("   Generated: \(summary.generatedDateFormatted)")
    print("   Summary length: \(summary.summary.count) chars")
} else {
    print("❌ No summary found")
}
```

### Test 3: Vérifier l'Utilisation dans les Questions

1. Générez un profil historique
2. Posez une question à l'IA (ex: "Comment puis-je améliorer mes performances?")
3. Vérifiez les logs:

**Logs attendus:**
```
✅ WorkoutAIService: Using historical summary (2847 chars)
```

### Test 4: Test du Refresh (après 3 mois)

```swift
// Pour tester, modifiez temporairement la date de génération
let storage = HistoricalSummaryStorage.shared
if var summary = storage.load() {
    // Modifier la date pour simuler 3 mois
    // Note: Vous devrez rendre `generatedDate` mutable pour ce test
}

// Vérifiez que needsRefresh est true
print(storage.needsGeneration()) // Devrait retourner true
```

## 📊 Coûts et Performance

### Coût Initial (One-Time)
```
365 workouts × 150 tokens = 54,750 tokens input
Résumé: ~2,000 tokens output

Coût: ~$0.013 par utilisateur (une seule fois)
```

### Coût par Message (Après Installation)
```
Résumé historique: ~2,000 tokens (cached)
Derniers 14 jours: ~280 tokens (fresh)
System prompt: ~500 tokens (cached)
Question: ~100 tokens

Total: ~2,880 tokens
Coût: ~$0.0003 par message (vs $0.003 sans optimisation)
```

### Économie
- **9.5× moins cher** que d'envoyer tous les workouts à chaque fois
- **$978/mois** pour 1,000 users (vs $9,324 sans optimisation)

## 🔍 Debug et Troubleshooting

### Le résumé n'est pas généré
1. Vérifiez les permissions HealthKit
2. Vérifiez que l'utilisateur a des workouts
3. Vérifiez les logs backend pour les erreurs API

### Le résumé n'est pas utilisé
1. Vérifiez que le résumé est bien sauvegardé:
   ```swift
   print(HistoricalSummaryStorage.shared.hasSummary)
   ```
2. Vérifiez les logs dans `buildChatPayload()`:
   ```
   ✅ WorkoutAIService: Using historical summary (XXX chars)
   ```

### Effacer le résumé (pour re-tester)
```swift
HistoricalSummaryStorage.shared.clear()
```

## 📈 Prochaines Améliorations

1. **Affichage du Profil**
   - Créer une vue "My Athletic Profile" pour afficher le résumé
   - Graphiques de progression
   - Comparaison temporelle

2. **Refresh Intelligent**
   - Détecter automatiquement les changements significatifs
   - Proposer un refresh si >20% d'amélioration détectée

3. **Historique des Résumés**
   - Garder plusieurs versions du résumé
   - "Your profile 3 months ago vs now"

4. **Export et Partage**
   - Permettre d'exporter le profil
   - Génération d'une image avec stats clés

## 📝 Notes de Déploiement

### Backend
1. Déployer le backend avec les nouveaux endpoints
2. Vérifier que l'endpoint `/api/analyze-history` fonctionne:
   ```bash
   curl -X POST https://insightrun-backend.mbenaissa.workers.dev/api/analyze-history \
     -H "Content-Type: application/json" \
     -H "X-App-Key: YOUR_KEY" \
     -d '{"workouts": [], "model": "x-ai/grok-4-fast", "language": "en"}'
   ```

### iOS
1. Les nouveaux fichiers doivent être ajoutés au target Xcode
2. Build et test sur device réel pour vérifier HealthKit
3. Test avec différents nombres de workouts (0, 10, 100, 365)

## ✅ Checklist de Validation

- [ ] Backend déployé avec `/api/analyze-history`
- [ ] Onboarding view affichée au premier lancement
- [ ] Progress bar fonctionne correctement
- [ ] Résumé sauvegardé localement
- [ ] Résumé utilisé dans les questions IA
- [ ] Bouton de régénération dans Settings
- [ ] Tests avec 0, 10, 100+ workouts
- [ ] Gestion des erreurs (rate limit, network, etc.)
- [ ] Logs de debug activés
- [ ] Performance acceptable (<20s pour 365 workouts)

## 🎉 C'est Prêt!

L'implémentation est complète. Il ne reste plus qu'à:
1. Intégrer `HistoricalAnalysisOnboardingView` dans votre flow
2. Déployer le backend
3. Tester le workflow complet

Pour toute question, référez-vous à ce document ou aux logs de debug.
