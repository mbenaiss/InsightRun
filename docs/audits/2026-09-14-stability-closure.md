# Audit de stabilité — vérifications complémentaires du 14 septembre 2026

Cette passe part de `main` au commit `a2d6180` (PR #104). Elle traite les cinq réserves de l’audit initial. Les PR #100 à #104 sont déjà fusionnées ; le build 340 soumis à Apple ne contient pas les changements décrits ici.

## Corrections

- **Dépendances web** : renouvellement des deux lockfiles Bun, retrait du lockfile npm obsolète du site, mises à jour compatibles des dépendances et résolution de PostCSS en `8.5.28`. Lint et builds Next.js/OpenNext réussis. Les audits Bun du backend, du site et de l’administration retournent chacun zéro alerte. Ce résultat décrit les avis connus au moment de la vérification.
- **FCmax** : le détail de séance et le contexte IA utilisent maintenant la même estimation `220 − âge`, avec un libellé explicite dans l’interface. L’âge vient de la date de naissance HealthKit ; s’il manque, aucun pourcentage ni zone n’est inventé. La FCmax observée pendant une séance n’est plus utilisée comme référence personnelle.
- **Analyses en cache** : version du contexte, référence cardiaque et signature d’un sous-ensemble stable des données de la séance enregistrées avec chaque analyse. Une analyse existante reste toujours affichée : si la version, la FCmax (au-delà de ±1 bpm) ou ces données changent, elle est signalée comme peut-être obsolète, avec une action « Régénérer » qui ne consomme une requête qu’au toucher. En cas d’échec réseau ou d’annulation, l’analyse précédente reste affichée. La migration de l’ancien schéma SwiftData est testée sur un fichier persistant.
- **Import FIT** : décodage et conversion sont effectués hors du thread principal. L’annulation est propagée au traitement ; elle est vérifiée avant le décodage et pendant la conversion. Le décodage interne de la bibliothèque n’est pas interruptible instantanément. Une fixture synthétique de 70 000 enregistrements conserve 210 km, 70 000 s et 210 splits, avec au plus 2 000 échantillons cardiaques gardés. Mesure locale indicative du parsing : environ 0,64 s sur le simulateur, sans garantie pour d’autres fichiers ou appareils.
- **Absence de données santé** : le conseil local du tableau de bord indique désormais que les données sont insuffisantes, au lieu d’interpréter le score de repli comme une bonne récupération.
- **Favicon administrateur** : icône déclarée et redirection de `/favicon.ico` vers `/favicon.png`. Les deux chemins aboutissent à une réponse HTTP 200 de type PNG dans le Worker local.

L’estimation cardiaque suit la référence déjà utilisée par le backend. Les nombres liés à l’âge sont des moyennes indicatives, comme le précise l’[American Heart Association](https://www.heart.org/en/healthy-living/fitness/fitness-basics/target-heart-rates).

## Vérifications complémentaires

| Parcours | Preuve et limites |
| --- | --- |
| Notification sur iPhone | Le vrai `NotificationManager` programme un déclencheur calendaire dans la minute suivante. Après passage en arrière-plan, la notification est retrouvée dans `deliveredNotifications`. Les tests de calendrier/concurrence couvrent le dimanche à 18 h. L’appareil n’a pas encore été observé le dimanche 20 septembre. |
| Achats StoreKit | Achat vérifié, restauration, expiration et erreurs de réseau testés avec la configuration StoreKit de l’app. Aucun paiement réel n’a été déclenché. |
| Restauration RevenueCat | Appel réel sur l’iPhone terminé sans erreur ; aucun abonnement actif n’est retourné pour ce compte de test. Cela ne démontre pas la restauration d’un abonnement payant actif. |
| Export WorkoutKit | La séance QA de trois étapes est acceptée par le planificateur iPhone. La capture fournie par l’utilisateur la montre dans Forme, avec échauffement 1 min, travail 2 min et retour au calme 1 min. L’affichage sur l’Apple Watch physique reste à confirmer ; la connexion directe à la montre est indisponible. |
| Hors ligne | Conservation du cache lors d’un échec de génération et récupération après retour du réseau vérifiées par tests. Le parcours physique avec erreurs réseau injectées attend le déverrouillage de l’iPhone. Une longue période réelle hors ligne n’est pas simulée par une simple modification de l’heure. |
| Migration | Ancienne base d’analyses sur disque migrée vers le nouveau modèle sans perte ; les anciennes analyses restent affichées et sont signalées comme à régénérer. |
| Refus des permissions et réinstallation | Parcours UI réussi sur un simulateur dédié : démarrage après installation, accès Santé refusé, navigation dans les quatre onglets, notifications refusées puis relancement sans blocage. Le refus du consentement IA est couvert par les tests UI permanents. |
| Web | Accueil, changement de thème, support et formulaire de connexion administrateur vérifiés dans le navigateur intégré sur les Workers compilés ; aucune erreur JavaScript observée sur ces parcours. |

## Validation finale locale

- **128 tests iOS réussis** : 97 tests principaux, 25 tests d’analyse et 6 parcours UI permanents. Zéro échec. Le parcours supplémentaire sans permissions est également réussi.
- **Build iOS Release réussi**. `swift-format lint` : zéro erreur, avertissements de style sur les fichiers examinés ; aucune remise en forme globale n’a été appliquée.
- **36 tests backend réussis**, lint/format Biome, TypeScript et build Worker réussis.
- **Site et administration** : lint sans erreur, builds Next.js/OpenNext réussis, contrôles navigateur sur les Workers compilés réussis.
- **Trois audits de dépendances à zéro alerte** et `git diff --check` réussi.

## Livraison et éléments dépendant de l’appareil

Les corrections et validations locales sont prêtes pour les pipelines de livraison. Le téléphone est détecté, mais iOS refuse son lancement à distance tant qu’il est verrouillé. Les scripts temporaires de validation et les captures privées sont conservés hors dépôt dans `/tmp/insightrun-stability-audit`. La séance et la notification QA doivent être retirées de l’iPhone après vérification.

Ces contrôles complètent les parcours d’écrans et mesures de chargement de la première passe. Ils ne constituent pas une certification de tous les écrans dans toutes les conditions, ni de l’absence future de crash.
