# 🎨 Système de Design de Couleurs pour InsightRun

## Vue d'ensemble de l'application

Application iOS de suivi de workouts de course à pied avec :
- Intégration HealthKit
- Design "Liquid Glass" (glassmorphisme iOS 26)
- Analyse AI des performances
- Métriques avancées de récupération

---

## 📊 Palette de Couleurs Recommandée

### 1. Couleurs Primaires (Brand Identity)

#### Bleu Principal (Primary Blue)
- **Light Mode**: `#007AFF` (iOS Blue)
- **Dark Mode**: `#0A84FF`
- **Usage**: Actions principales, navigation, FAB

#### Bleu Secondaire (Accent Cyan)
- **Light Mode**: `#32ADE6`
- **Dark Mode**: `#64D2FF`
- **Usage**: Dégradés, états actifs, highlights

#### Noir/Blanc (Base)
- **Background Light**: `#F2F2F7`
- **Background Dark**: `#000000`
- **Card Light**: `#FFFFFF` avec opacity 0.7-0.9
- **Card Dark**: `#1C1C1E` avec opacity 0.7-0.9

---

### 2. Couleurs Métriques Cardio 💓

#### Rouge Cardiaque (Heart Rate)
- **Primary**: `#FF3B30` (iOS Red)
- **Light**: `#FF6961`
- **Dark**: `#D70015`
- **Usage**: Fréquence cardiaque, zones d'intensité max

#### Rose Cardiaque (Heart Gradient)
- **Pink**: `#FF375F`
- **Coral**: `#FF6482`
- **Usage**: Dégradés cardio, graphiques HR

#### Zones de Fréquence Cardiaque
| Zone | Nom | Couleur | Hex |
|------|-----|---------|-----|
| 1 | Récupération | Vert | `#34C759` |
| 2 | Aérobie | Vert clair | `#30D158` |
| 3 | Tempo | Jaune | `#FFD60A` |
| 4 | Seuil | Orange | `#FF9500` |
| 5 | Max | Rouge | `#FF3B30` |

---

### 3. Couleurs Performance 🏃

#### Bleu Performance (Pace/Speed)
- **Primary**: `#007AFF`
- **Gradient Start**: `#007AFF`
- **Gradient End**: `#00C7BE` (Cyan)
- **Usage**: Allure, vitesse, cadence

#### Vert Positive (Achievements)
- **Primary**: `#34C759` (iOS Green)
- **Light**: `#30D158`
- **Usage**: PR, progrès, métriques positives

#### Orange Énergie (Power/Effort)
- **Primary**: `#FF9500` (iOS Orange)
- **Light**: `#FFCC00`
- **Usage**: Effort, puissance, avertissements

---

### 4. Couleurs Récupération 😴

#### Indigo Sommeil (Sleep)
- **Primary**: `#5856D6` (iOS Indigo)
- **Deep Sleep**: `#5856D6`
- **Light Sleep**: `#5AC8FA` (Cyan)
- **REM Sleep**: `#AF52DE` (Purple)
- **Usage**: Sommeil, repos, récupération nocturne

#### Teal Respiration (Respiratory)
- **Primary**: `#30B0C7`
- **Light**: `#5AC8FA`
- **Usage**: Respiration, fréquence respiratoire

#### Vert Récupération (Recovery Score)
| Score | Niveau | Couleur | Hex |
|-------|--------|---------|-----|
| 80-100 | Excellent | Vert | `#34C759` |
| 60-79 | Bon | Jaune | `#FFD60A` |
| 40-59 | Moyen | Orange | `#FF9500` |
| 0-39 | Faible | Rouge | `#FF3B30` |

---

### 5. Couleurs Élévation/Terrain ⛰️

#### Gradient Élévation
- **Bas**: `#34C759` (Vert)
- **Moyen**: `#007AFF` (Bleu)
- **Haut**: `#5856D6` (Indigo)

#### Gradient Chaleur (Heatmap)
- **Cool**: `#5AC8FA` (Cyan)
- **Warm**: `#FF9500` (Orange)
- **Hot**: `#FF3B30` (Rouge)

---

### 6. Couleurs Sémantiques ✅

#### Succès (Success)
- **Color**: `#34C759`
- **Usage**: Objectifs atteints, confirmations

#### Avertissement (Warning)
- **Color**: `#FF9500`
- **Usage**: Alertes modérées, attention

#### Erreur (Error)
- **Color**: `#FF3B30`
- **Usage**: Erreurs, actions destructives

#### Information (Info)
- **Color**: `#007AFF`
- **Usage**: Tips, informations neutres

---

### 7. Couleurs Glassmorphisme 🔮

#### Ombres (Shadows)
- **Light Mode**: `rgba(0, 0, 0, 0.05)`
- **Dark Mode**: `rgba(0, 0, 0, 0.3)`
- **Specs**: radius 10-12, y-offset 5-6

#### Matériaux (Materials)
- **Ultra Thin**: `.ultraThinMaterial`
- **Thin**: `.thinMaterial`
- **Regular**: `.regularMaterial`
- **Usage**: Cartes, overlays, backgrounds

#### Opacités (Glass Effect)
- **Cards Light**: 0.7-0.9
- **Cards Dark**: 0.6-0.8
- **Overlays**: 0.3-0.5
- **Borders**: 0.1-0.2

---

## 🌈 Dégradés Recommandés

### Bouton Principal (FAB)
```swift
LinearGradient(
    colors: [Color(hex: "007AFF"), Color(hex: "32ADE6")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

### Header Cardio
```swift
LinearGradient(
    colors: [Color(hex: "FF375F"), Color(hex: "FF6482")],
    startPoint: .leading,
    endPoint: .trailing
)
```

### Performance Metrics
```swift
LinearGradient(
    colors: [Color(hex: "007AFF"), Color(hex: "00C7BE")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

### Récupération
```swift
LinearGradient(
    colors: [Color(hex: "34C759"), Color(hex: "30B0C7")],
    startPoint: .leading,
    endPoint: .trailing
)
```

### Sommeil
```swift
LinearGradient(
    colors: [Color(hex: "5856D6"), Color(hex: "AF52DE")],
    startPoint: .leading,
    endPoint: .trailing
)
```

---

## 🎯 Recommandations par Écran

### WorkoutListView
- **Background**: `.ultraThinMaterial` avec `#F2F2F7` (light) / `#000000` (dark)
- **Cards**: Blanc avec opacity 0.8 + ombre légère
- **FAB**: Dégradé bleu → cyan
- **Texte principal**: `.primary` (adaptatif)
- **Métriques**: Couleurs sémantiques selon le type

### WorkoutDetailView
- **Header Cardio**: Dégradé rouge-rose
- **Splits Performance**: Alternance vert/bleu/orange selon la performance
- **Graphiques**: Utiliser les couleurs métriques correspondantes
- **Icônes**: Correspondre à la couleur de la métrique

### RecoveryDashboardView
- **Recovery Score**: Couleur dynamique selon le score (vert/jaune/orange/rouge)
- **Sommeil**: Palette indigo-purple
- **HRV**: Bleu
- **Fréquence de repos**: Rouge doux

### WorkoutAIAssistantView
- **Messages AI**: Bleu pour les insights positifs, orange pour les recommandations
- **Coaching**: Vert pour les félicitations
- **Tips**: Cyan pour l'information

---

## ♿ Accessibilité & Contraste

### Ratios de Contraste WCAG AA

#### Texte sur fond clair
- **Primary Text**: ratio ≥ 4.5:1
- **Large Text**: ratio ≥ 3:1
- **Recommandation**: Utiliser `.primary`, `.secondary` SwiftUI colors

#### Texte sur fond sombre
- **Primary Text**: ratio ≥ 4.5:1
- **Recommandation**: Préférer les couleurs plus claires

#### Sur verre/glassmorphisme
- **Recommandation**: Ajouter un fond semi-opaque pour améliorer la lisibilité

### Modes d'accessibilité
- ✅ Supporter **Increase Contrast** iOS
- ✅ Supporter **Reduce Transparency**
- ✅ Vérifier avec **Color Blind Simulator**

---

## 📱 Mode Clair vs Mode Sombre

| Élément | Mode Clair | Mode Sombre |
|---------|------------|-------------|
| Background | `#F2F2F7` | `#000000` |
| Cards | White 0.8 opacity | `#1C1C1E` 0.7 opacity |
| Primary Blue | `#007AFF` | `#0A84FF` |
| Text Primary | Black | White |
| Text Secondary | Gray 60% | Gray 70% |
| Shadows | Black 5% | Black 30% |
| Dividers | Gray 20% | Gray 30% |

---

## 🏗️ Structure Recommandée

### Créer ces fichiers dans le projet

```
HealthApp/ThemeManager/
├── ColorPalette.swift
│   ├── Couleurs primaires
│   ├── Couleurs métriques
│   ├── Couleurs sémantiques
│   └── Mode clair/sombre
│
├── GradientDefinitions.swift
│   ├── Dégradés prédéfinis
│   └── Helpers pour créer des gradients
│
├── MetricColors.swift
│   ├── Couleurs par type de métrique
│   ├── Couleurs par zone (HR zones)
│   └── Couleurs dynamiques (scores)
│
└── DesignTokens.swift
    ├── Spacing
    ├── Corner radius
    ├── Shadow styles
    └── Material styles
```

### Dans Assets.xcassets

```
Assets.xcassets/Colors/
├── Brand/
│   ├── PrimaryBlue.colorset
│   ├── AccentCyan.colorset
│   └── BackgroundBase.colorset
│
├── Metrics/
│   ├── HeartRed.colorset
│   ├── PerformanceBlue.colorset
│   ├── RecoveryGreen.colorset
│   ├── SleepIndigo.colorset
│   └── ElevationGreen.colorset
│
├── Semantic/
│   ├── Success.colorset
│   ├── Warning.colorset
│   ├── Error.colorset
│   └── Info.colorset
│
└── Glassmorphism/
    ├── CardBackground.colorset
    ├── ShadowColor.colorset
    └── BorderColor.colorset
```

---

## 💡 Best Practices

### 1. Cohérence
- ✅ Toujours utiliser les couleurs définies dans le système
- ❌ Éviter les couleurs hardcodées
- ✅ Utiliser les couleurs sémantiques pour les actions (success, error, etc.)

### 2. Hiérarchie Visuelle
- ✅ Couleurs vives pour les actions principales
- ✅ Couleurs douces pour le contenu secondaire
- ✅ Utiliser l'opacité pour créer de la profondeur

### 3. Glassmorphisme
- ✅ Maintenir la cohérence des ombres (radius 10-12, offset y: 5-6)
- ✅ Utiliser `.ultraThinMaterial` pour les cartes
- ✅ Opacité 0.7-0.9 pour les backgrounds de carte

### 4. Dégradés
- ✅ Utiliser pour les boutons principaux et les headers
- ❌ Ne pas en abuser (max 2-3 par écran)
- ✅ Toujours dans la même famille de couleurs

### 5. Dark Mode
- ✅ Tester toutes les couleurs en mode sombre
- ✅ Ajuster la luminosité si nécessaire
- ✅ Utiliser des couleurs plus claires en dark mode

---

## 🎨 Exemples de Code

### Extension Color pour Hex
```swift
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

### ViewModifier pour Cartes Glassmorphiques
```swift
struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(
                color: colorScheme == .light ?
                    Color.black.opacity(0.05) :
                    Color.black.opacity(0.3),
                radius: 10,
                y: 5
            )
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}
```

### Utilisation
```swift
VStack {
    Text("Mon contenu")
}
.glassCard()
```

---

## 🚀 Prochaines Étapes Suggérées

### Phase 1 : Fondations
1. ✅ Créer le fichier `ColorPalette.swift` avec toutes les couleurs définies
2. ✅ Ajouter les color sets dans `Assets.xcassets`
3. ✅ Créer l'extension `Color(hex:)` pour les couleurs custom

### Phase 2 : Système de Design
4. ✅ Créer `GradientDefinitions.swift` pour les dégradés réutilisables
5. ✅ Implémenter `MetricColors.swift` pour mapper métriques → couleurs
6. ✅ Créer `DesignTokens.swift` pour spacing, radius, shadows

### Phase 3 : Migration
7. ✅ Remplacer progressivement les couleurs hardcodées par le système
8. ✅ Commencer par WorkoutDetailView (34 occurrences)
9. ✅ Puis RecoveryDashboardView (26 occurrences)

### Phase 4 : Tests & Validation
10. ✅ Tester l'accessibilité avec VoiceOver
11. ✅ Valider avec Color Blind Simulator
12. ✅ Tester en mode sombre sur tous les écrans

---

## 📚 Ressources

### Design Guidelines
- [Apple Human Interface Guidelines - Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [iOS Color Palette](https://developer.apple.com/design/human-interface-guidelines/color#iOS-iPadOS)
- [WCAG 2.1 Contrast Guidelines](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html)

### Outils
- [Contrast Checker](https://webaim.org/resources/contrastchecker/)
- [Color Blind Simulator](https://www.color-blindness.com/coblis-color-blindness-simulator/)
- [iOS Color Picker](https://developer.apple.com/design/resources/)

---

## 📝 Notes

- Cette proposition respecte les guidelines iOS
- Supporte le dark mode nativement
- Optimisée pour une application de santé/fitness
- Compatible avec le design glassmorphique moderne
- Testée pour l'accessibilité WCAG AA

---

**Créé le**: 2025-10-22
**Version**: 1.0
**Auteur**: Recommandations pour InsightRun iOS App
