# Courses officielles — 14 septembre 2026

L’utilisateur souhaite identifier uniquement les courses déjà réalisées, les retrouver avec un filtre et les voir dans ses plans d’entraînement.

## Comportement

- Le détail d’une séance comporte un interrupteur « Course officielle », activable et désactivable.
- Le filtre « Courses officielles » consulte toutes les dates de l’historique disponible. Les courses portent un badge et leur nom d’origine lorsqu’il existe ; la recherche inclut ce nom.
- Les semaines du plan affichent les courses réalisées pendant leur période, avec date, distance et durée. Une course faite un jour de repos apparaît également. Le marquage ne modifie ni les séances prévues ni leur statut de réalisation.
- Le stockage local est distinct du cache HealthKit/Strava. Les identifiants des sources sont rapprochés lors de la synchronisation pour conserver le marquage après fusion. Aucun statut n’est écrit dans Strava ou Apple Santé.
- Les libellés sont traduits en français, anglais et espagnol. Cette fonctionnalité n’ajoute pas de synchronisation des marquages entre plusieurs appareils.

## Validation

- 118 tests iOS passent : 92 tests principaux, 20 tests d’analyse et 6 tests UI.
- Cinq tests unitaires couvrent la persistance, le retrait, les alias HealthKit/Strava, la fusion de doublons, le filtre multi-mois et les limites de semaine avec changement d’heure.
- Le test UI du plan utilise des données de test et vérifie l’apparition puis le retrait de la course dans le composant réellement utilisé par les plans.
- Sur l’iPhone réel, le parcours marquage → filtre → relancement → vérification → retrait passe. Les captures ont été inspectées ; la séance utilisée pour l’essai a été remise dans son état initial.
- Build Release local et lint exécutés. Le lint conserve les avertissements de style existants ; aucune erreur de lint et aucune remise en forme globale.
- Les captures privées et le script propre aux données de l’iPhone restent hors dépôt.

## Compilation de livraison

L’archive Xcode Cloud 335 a échoué dans l’optimiseur Swift 6.3.3, lors de l’optimisation du destructeur isolé implicite du type générique `ConcurrentRequestCoalescer`. Le destructeur vide est désormais explicitement non isolé. La compilation Release locale avec Swift 6.4 passe ; l’archive distante doit également être validée avant soumission.

Les propriétés des événements MetricKit sont capturées par valeur avant leur envoi sur l’acteur principal, ce qui élimine les avertissements de capture mutable observés pendant la compilation Release.
