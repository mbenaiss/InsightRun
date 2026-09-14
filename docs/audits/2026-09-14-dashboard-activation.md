# Carte de première consultation — 14 septembre 2026

La carte « Analyser ma dernière course » restait visible après consultation d’une séance. Le détail enregistrait déjà cette première consultation, mais le tableau de bord ne consultait pas cet état.

Le tableau de bord observe désormais la même préférence persistante et masque la section « Prochaine action » dès la première consultation. Elle reste masquée après relancement. Cette carte guide la première utilisation ; elle ne représente pas le statut d’analyse de chaque nouvelle course.

## Validation

- Les 118 tests iOS passent : 92 tests principaux, 20 tests d’analyse et 6 tests UI.
- Le test UI d’activation vérifie la présence initiale de la carte, l’ouverture du détail, sa disparition au retour et sa persistance après relancement. La remise à zéro de la préférence est réservée au mode démonstration en compilation Debug.
- Sur l’iPhone réel, un test supplémentaire passe avec les données existantes : carte absente, ouverture d’une séance, retour au tableau de bord et relancement. Les captures ont été inspectées ; le script et les captures privées restent hors dépôt.
- La compilation Release réussit. Le lint ne signale aucune erreur ; les avertissements de style existants demeurent.

La couverture globale des chargements et les scénarios non exercés sont documentés dans [la revue par écran](2026-09-14-screen-loading.md). Ce correctif ne constitue pas une validation exhaustive de tous les écrans et états de l’application.
