# HealthApp - iOS 26 Running Workouts

Application iOS 26 pour afficher et analyser vos workouts de course depuis HealthKit.

## Prérequis

- **Xcode 16+** avec iOS 26 SDK
- **iOS 26+** sur appareil physique (HealthKit ne fonctionne pas correctement sur simulateur)
- **iPhone 11 ou ultérieur** (A13 Bionic minimum)

## Installation

### 1. Créer le projet Xcode

1. Ouvrir Xcode
2. File → New → Project
3. Choisir **"iOS App"**
4. Configurer :
   - **Product Name**: `HealthApp`
   - **Team**: Votre équipe de développement
   - **Organization Identifier**: `com.yourcompany` (ou autre)
   - **Interface**: **SwiftUI**
   - **Language**: **Swift**
   - **Minimum Deployment**: **iOS 26.0**
5. Enregistrer dans ce dossier

### 2. Ajouter la capability HealthKit

1. Sélectionner le projet dans la sidebar
2. Target → HealthApp
3. Onglet **"Signing & Capabilities"**
4. Cliquer **"+ Capability"**
5. Ajouter **"HealthKit"**

### 3. Configurer Info.plist

Ajouter ces clés dans `Info.plist` :

```xml
<key>NSHealthShareUsageDescription</key>
<string>Cette app a besoin d'accéder à vos données de course pour afficher votre historique d'entraînement.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Cette app ne modifie pas vos données de santé.</string>
```

### 4. Remplacer les fichiers générés

Supprimer `ContentView.swift` généré par Xcode, et garder uniquement les fichiers de ce repo.

Assurer que tous les fichiers sont ajoutés au target dans Xcode :
- Sélectionner tous les fichiers .swift
- File Inspector → Target Membership → Cocher "HealthApp"

### 5. Build & Run

1. Connecter un iPhone physique
2. Sélectionner votre device
3. Cmd+R pour build and run
4. Accepter les permissions HealthKit
5. Vos workouts de course s'afficheront !

## Structure du projet

```
HealthApp/
├── HealthAppApp.swift          # Entry point
├── Models/
│   ├── WorkoutModel.swift      # Workout data structure
│   └── WorkoutMetrics.swift    # Detailed metrics & stats
├── Services/
│   └── HealthKitManager.swift  # HealthKit integration layer
├── ViewModels/
│   ├── WorkoutListViewModel.swift
│   └── WorkoutDetailViewModel.swift
└── Views/
    ├── WorkoutListView.swift   # Main list screen
    ├── WorkoutRowView.swift    # List item component
    └── WorkoutDetailView.swift # Detail screen with all data
```

## Fonctionnalités

### Liste des workouts
- Affichage de tous les workouts de course
- Tri par date (plus récent en premier)
- Pull-to-refresh
- Design Liquid Glass (iOS 26)

### Détail d'un workout
- **Données de base**: Distance, durée, calories, allure
- **Fréquence cardiaque**: Moyenne, min, max, zones
- **Performance**: Vitesse, cadence, longueur de foulée, puissance
- **Splits**: Par kilomètre avec allure
- **Élévation**: Dénivelé total
- **Route GPS**: Tracé complet (si disponible)

## Design

Application avec design **Liquid Glass** (iOS 26) :
- Éléments translucides et arrondis
- Effets de verre avec réfraction
- Animations subtiles et réactives
- Palette minimaliste

## Troubleshooting

### Pas de workouts affichés
- Vérifier que vous avez des workouts de type "Running" dans l'app Santé
- Vérifier les permissions HealthKit (Réglages → Confidentialité → Santé)

### HealthKit non disponible
- HealthKit nécessite un appareil physique
- Pas disponible sur simulateur (ou données limitées)

### Build errors
- Vérifier que le deployment target est bien iOS 26+
- Vérifier que tous les fichiers sont dans le target
- Clean build folder (Cmd+Shift+K)

## Technologies

- **SwiftUI** - Interface utilisateur
- **HealthKit** - Accès aux données de santé
- **Combine** - Gestion de l'état réactif
- **Swift Concurrency** - async/await pour les opérations asynchrones
- **MapKit** - Affichage des tracés GPS (si implémenté)

## License

Private project
