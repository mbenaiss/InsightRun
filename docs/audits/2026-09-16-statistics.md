# Statistiques — audit et améliorations du 16 septembre 2026

## Corrections

- Le bilan, les graphiques et les répartitions suivent la période choisie. Le mois en cours est comparé à la même portion écoulée du mois précédent, avec les dates affichées.
- Les fenêtres de 6 et 12 mois utilisent le calendrier. Les semaines sans séance restent visibles ; aucune période future vide ne fait artificiellement chuter le graphique.
- L’allure moyenne est pondérée par la distance et identique dans le bilan et Progression. Les distances/durées invalides sont exclues des calculs concernés.
- Les records sont explicitement calculés sur l’historique complet et correspondent à des séances complètes, pas à des meilleurs segments intermédiaires.
- Les erreurs de lecture conservent les données déjà disponibles et proposent de réessayer. Une période vide permet de revenir à toutes les courses.

## Chargement et contenu

- Agrégats et répartitions mis en cache ; requêtes Santé simultanées regroupées ; retour rapide dans l’onglet sans relire immédiatement tout l’historique.
- L’allure apparaît dès que la liste des séances est disponible. Les métriques supplémentaires se chargent par lots de quatre séances, réutilisent leur cache et ignorent les résultats d’une ancienne sélection.
- Les chargements Progression s’arrêtent à la sortie de l’écran et reprennent au retour. Les anciens lots finissent avant les suivants pour éviter d’accumuler les requêtes après des changements de filtre rapides.
- La « Meilleure allure » est retirée des records et de Progression à la demande de l’utilisateur. La requête détaillée d’allure correspondante est supprimée de ce parcours.
- Six requêtes Santé de mobilité supprimées par séance dans ce parcours. Les courbes de marche et la vitesse maximale, redondante avec la meilleure allure, sont retirées de Progression.
- Les graphiques de progression rendent au plus 160 points en conservant les extrêmes et les bornes ; les calculs et la sélection utilisent toujours les données complètes.
- Les sections et le carrousel utilisent une disposition simple : le test de défilement a révélé une boucle de mise en page des conteneurs différés imbriqués après le retrait d’une carte. Le nombre de cartes est borné et les séries restent échantillonnées pour le rendu.
- Les chiffres de la période apparaissent avant les records. Les plages d’allure remplacent les zones d’entraînement arbitraires. La répartition des distances indique le nombre de séances représentées.
- Le résumé mensuel IA est généré sur demande. Son cache tient compte des deux périodes et des modifications de distance/durée à identifiant constant. Une réponse incomplète ne remplace pas le résumé sauvegardé.
- Affichage des distances et allures adapté aux miles ; libellés et pluriels français/anglais corrigés.

## Mesures et validation

- Même banc d’essai local avant/après : 2 000 séances, 20 lectures des indicateurs et répartitions. Avant : **395,4 ms**. Après : **22,3 à 28,5 ms** selon l’exécution, soit environ **14 à 18 fois moins de temps de calcul**. Cette mesure ne couvre ni les accès Santé réels, ni le réseau, ni la fréquence d’affichage.
- Compilation iOS Simulator réussie ; **186 tests réussis**, dont **18 tests unitaires Statistiques et un test de défilement UI** couvrant calendriers et changements d’heure, données invalides, caches, concurrence, annulation, résumé IA et migration du stockage SwiftData existant.
- Lint Swift des fichiers concernés sans avertissement ; `git diff --check` réussi.
- Parcours XCTest sur simulateur iPhone 17 Pro/iOS 26.2 : périodes semaine/mois/tout, défilement, Progression, changements rapides de filtre, retour depuis le tableau de bord ; captures en français sombre/clair et anglais avec unités impériales.

## Limites vérifiées

- Les statistiques utilisent les courses présentes dans **Apple Santé**. La source est maintenant indiquée dans la page ; les séances uniquement conservées dans Strava ou Suunto ne sont pas ajoutées par ce changement.
- La vérification visuelle utilise des données de démonstration. Aucun test de performances sur iPhone physique ni nouvel appel IA de production n’a été effectué pour cette page.
- Deux avertissements StoreKit apparaissent dans les tests d’achat existants, sans échec ; ils sont indépendants de Statistiques.
- Les changements restent limités à Statistiques et à sa lecture mensuelle. Le travail simultané sur le tableau de bord est conservé dans une branche distincte.

## Version préparée

- Version iOS **2.0.9**, numéro de build local **345**, app et extensions alignées. Xcode Cloud utilise sa propre numérotation pour la distribution.
- Version **2.0.9** créée dans App Store Connect en préparation de soumission, avec publication manuelle. Métadonnées de 2.0.8 reprises et nouveautés actualisées en français, anglais et espagnol.
