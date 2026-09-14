# Revue des chargements par écran — 14 septembre 2026

Cette passe complète l’audit de stabilité et la première optimisation des statistiques. Les chemins de chargement des écrans listés ci-dessous ont été lus. La colonne iPhone distingue les parcours réellement exercés des écrans examinés dans le code : elle ne constitue pas une validation de tous les scénarios métier.

## Couverture

| Écran ou parcours | Chargement examiné et résultat | Vérification sur l’iPhone |
| --- | --- | --- |
| Démarrage et tableau de bord | Préchargement léger du coach ; dernière course et séance prévue indépendantes des appels IA ; pas de génération du texte du bilan hebdomadaire à l’ouverture du tableau de bord. | Oui |
| Liste des entraînements HealthKit / Strava | Cache local puis actualisation ; partage des requêtes simultanées de l’historique HealthKit ; huit recherches de score d’effort au maximum à la fois. | Oui, avec les données de cet appareil |
| Détail d’une course et analyse | Mesures déjà disponibles visibles pendant l’enrichissement Strava ; garde contre la génération initiale multiple ; analyses locales puis serveur. | Oui, détail et analyse en cache |
| Carte du parcours et lieu | Carte à partir des points déjà chargés ; géocodage avec cache et vérification d’annulation. | Inspection du détail ; pas de navigation cartographique exhaustive |
| Comparaison de courses | Comparaisons calculées depuis les séances présentes ; lecture locale du texte IA ; génération sur demande. | Code uniquement |
| Statistiques générales | Suppression des recherches de scores d’effort inutilisées ; graphiques conservés pendant l’actualisation. | Oui ; mesure avant/après dans l’audit principal |
| Progression | Cache par course, lots de huit, annulation lors du changement de période et publication progressive. | Oui |
| Récupération et graphiques du tableau de bord | Requêtes simultanées du même jour partagées ; effort, calories totales et répartition réutilisent un historique commun, lu séquentiellement. | Oui, tableau de bord |
| Calendrier de récupération | Tâche liée au mois affiché ; arrêt des anciennes lectures et publication des scores jour par jour. | Oui, plusieurs changements de mois puis fermeture |
| Bilan hebdomadaire | Réutilisation du modèle du tableau de bord, conservation du contenu lors d’un rafraîchissement ; délai minimal de 60 s entre lectures automatiques ; actualisation explicite conservée. Texte du coach chargé dans le bilan. | Oui, ouverture et défilement |
| Explications des scores et signaux | Courbes déjà fournies à la fiche ; analyse IA et cache pilotés par ScoreAnalysisViewModel. | Code et tests du modèle ; pas toutes les fiches physiques |
| Objectifs | Stockage local immédiat ; rattrapage des séances limité à une fois toutes les cinq minutes. | Oui, liste |
| Création et détail d’un objectif | Formulaire local ; analyse de l’historique au passage à l’étape profil ; adaptation du plan seulement pour un objectif actif doté d’un plan. | Code uniquement ; aucun objectif réel ajouté |
| Calendrier d’entraînement et séance planifiée | Semaines en LazyVStack ; détail alimenté par le plan déjà chargé ; export déclenché explicitement. | Code et tests de modèles ; pas d’export réel vers une montre |
| Génération de séance | Formulaire immédiat ; génération et proposition IA à la demande, avec états de progression. | Code et tests ; pas de nouvelle génération réelle |
| Coach et historique de conversation | Contexte détaillé au premier accès ; historique local ; streaming avec validation des réponses incomplètes. | Oui, ouverture/fermeture du coach |
| Réglages et sources médicales | Données locales ; vérification asynchrone de l’autorisation des notifications ; contenu médical statique. | Oui, réglages ; sources lues dans le code |
| Connexion Strava | OAuth à la demande ; conservation des identifiants sur panne temporaire. Le backend corrigé répond HTTP 200 lors d’une lecture réelle hors cache après déploiement. | Pas de reconnexion imposée |
| Import Suunto / FIT | Import déclenché par fichier ou action explicite ; progression et annulation examinées. | Pas de fichier réel importé |
| Indexation de l’historique | Lots, checkpoints et reprise ; rejet des résumés vides ; tâche annulable. | Code et tests ; pas de réindexation forcée des données personnelles |
| Onboarding, consentement et abonnement | Écrans locaux et composants RevenueCat ; appels réseau liés aux autorisations, produits et transactions. | Tests UI d’activation/consentement sur simulateur ; pas d’achat réel |

## Validation

- 111 tests sur simulateur : 87 tests principaux, 20 tests d’analyse et 4 tests UI d’activation.
- Cinq nouveaux tests vérifient le partage d’une requête, la propagation d’une erreur et la reprise, l’indépendance des clés, la cohérence des graphiques et l’absence de cache bloquant après une première lecture vide.
- Deux parcours étendus sur l’iPhone ont réussi. Une première tentative du calendrier a été interrompue par une bannière iOS provenant d’une autre application ; le parcours a ensuite réussi en contrôlant sa fermeture avant de continuer.
- Le lint Swift ne signale pas d’erreur mais conserve les nombreux avertissements de style du dépôt. Aucune remise en forme globale n’a été appliquée.
- Les scripts liés aux libellés et données de cet iPhone restent hors dépôt après leur exécution.

## Portée des résultats

La mesure quantitative disponible concerne les statistiques : médiane 5,81 s avant contre 3,46 s après la première passe, sur trois lancements et avec les délais XCTest inclus. Les autres améliorations retirent des attentes et requêtes identifiées dans le code ; aucun pourcentage de gain général n’est déduit pour toute l’app.

Les comptes sans données, très gros historiques, transactions réelles, imports volumineux et conditions réseau prolongées nécessitent des essais distincts. Aucun de ces cas n’est déclaré validé de bout en bout ici.
