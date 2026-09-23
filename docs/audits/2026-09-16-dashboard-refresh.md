# Dashboard — cohérence et rafraîchissement, 16 septembre 2026

## Corrections

- Le calendrier et le balayage changent désormais la date de l'ensemble du Dashboard : activité, effort, charge cardiaque, récupération, disponibilité, tendances et semaine affichée. Les réponses d'un chargement annulé ne remplacent plus la journée sélectionnée.
- La disponibilité passée utilise les scores enregistrés à cette date. Une valeur absente reste indisponible, sans zéro artificiel ni reprise du score d'aujourd'hui. Le calendrier utilise ce même historique local.
- Le statut de disponibilité est identique sur la card et son détail. Les tendances des constantes utilisent les mêmes mesures que les valeurs principales. Les comparaisons utilisent des données réelles ; le repère « hier » exige une mesure de la veille.
- Les détails reçoivent les données actualisées. Leur analyse est mise en cache par date, langue, valeur et contexte pertinent ; les identifiants aléatoires des points ne provoquent plus d'appels supplémentaires. Un changement de répartition des calories invalide l'analyse même si le total reste identique.
- Le score de disponibilité est figé pour la journée calendaire, quelle que soit la langue de l'application. L'activité, les constantes mesurées en journée (fréquence cardiaque au repos et à la marche, SpO₂, respiration) et le recalcul quotidien de la référence personnelle actualisent seulement le coaching ; le score figé reste envoyé au backend, qui n'applique donc pas de pénalité d'effort tardive. Seules des données de la nuit arrivées en retard (sommeil, VFC nocturne) autorisent un nouveau calcul. Les anciennes entrées de cache restent décodables et un score déjà obtenu avant la mise à jour reste figé.
- Le bilan hebdomadaire compare des périodes de même durée, utilise les mesures de la semaine sélectionnée pour ses moyennes et courbes, et efface les anciennes valeurs devenues absentes. Les détails de sommeil et de récupération partagent les données déjà chargées.
- La somme des calories actives et au repos affichées correspond au total arrondi. Les références de cette card concernent maintenant les énergies HealthKit, au lieu du sommeil.

## Déclenchements

| Événement | Comportement |
| --- | --- |
| Première apparition ou changement de jour | Un chargement coordonné pour la date sélectionnée ; annulation du précédent si nécessaire. |
| Retour au premier plan ou au Dashboard | Rafraîchissement automatique espacé d'au moins 60 secondes pour la même date ; conservation des jours historiques en cache pendant une heure. |
| Passage à un nouveau jour | Retour au nouveau jour uniquement si le Dashboard affichait encore l'ancien « aujourd'hui ». Une date passée explicitement sélectionnée est conservée. |
| Tirer pour actualiser | Invalidation complète des données de tendances et actualisation forcée. |
| Nouvelle course ou suppression signalée par HealthKit | Actualisation forcée lorsque l'application est active. |
| Consentement IA accepté ou indexation terminée | Actualisation immédiate, sans attendre le délai automatique. |
| Ouverture d'une card | Réutilisation des mesures ; appel d'analyse uniquement si le cache de son contexte manque. |
| Ouverture du calendrier | Lecture des scores locaux, sans chargement HealthKit de tout le mois. |
| Ouverture du bilan hebdomadaire | Chargement des détails et du coaching à ce moment-là. |

## Mesures sur l'iPhone

Instrumentation Debug activée uniquement avec `-DASHBOARD_DIAGNOSTICS`. Les compteurs portent sur les chargements journaliers des services et les entrées des appels d'analyse ; un chargement journalier peut contenir plusieurs requêtes HealthKit internes. Ce relevé ne constitue pas une capture exhaustive de tous les échanges réseau des SDK.

- Au chargement : **7 chargements journaliers d'activité et 7 de récupération** alimentent toutes les tendances. La journée courante est partagée avec les cards ; les autres jours sont mutualisés entre les graphiques.
- Le bilan détaillé ajoute **3 jours de récupération** manquants pour la comparaison avec la semaine précédente, dans le cas observé un mercredi.
- Au retour de ce bilan, après plus de 60 secondes : **1 chargement d'activité et 1 de récupération**, sans relire les six jours passés.
- Lors du premier parcours instrumenté, chaque détail a déclenché au plus une analyse. Au second parcours complet, les **9 cards ont réutilisé leur cache : aucun appel d'analyse de score ni de disponibilité**.
- Les sélections de dates passées n'appellent pas le calcul de disponibilité quotidienne du backend. Le rafraîchissement manuel force bien un nouveau calcul du jour courant.

Les mesures de santé et les captures privées restent hors dépôt, dans les résultats XCTest locaux.

## Validation

- **189 tests sur simulateur réussis, 0 échec, 0 ignoré** : suites principales, analyses, activation et nouveaux parcours Dashboard. Les régressions couvrent notamment la concurrence, l'annulation lors du changement de date, la mutualisation des lectures, l'invalidation des caches et les scores historiques absents. Les 46 tests ciblés de tendances et d'analyse ont été rejoués après le dernier ajustement de l'initialisation du cache et passent également.
- Sur l'iPhone réel : ouverture des cards disponibilité, effort, sommeil, VFC, fréquence cardiaque au repos, respiration, saturation, charge cardiaque et calories ; défilement des détails, graphiques, composantes et références ; ouverture et défilement du bilan hebdomadaire. Captures inspectées.
- **5 parcours XCTest sur l'iPhone réussis** : cards et bilan ; balayage hier/aujourd'hui, détail du coach et ouverture du formulaire de plan ; réouverture de l'effort, hier et une date du mois précédent, retour à aujourd'hui et changement d'onglet ; rafraîchissement manuel et conservation d'une date passée après passage en arrière-plan ; attente de la fin d'un rafraîchissement manuel avec vérification du nouvel horodatage du coach et d'un unique appel de disponibilité. Le formulaire de plan a été ouvert puis fermé sans génération.
- Builds iPhone Debug et simulateur Release réussis. Lint `swift-format` exécuté sur les fichiers Swift modifiés : aucune erreur, avertissements de style présents. `git diff --check` passe.

Le compte de l'iPhone dispose de données de sommeil. Les variantes fraîcheur et construction de référence, l'arrivée physique d'une nouvelle séance pendant l'affichage et le passage réel à minuit n'ont pas été reproduits sur cet appareil. Les vérifications portent sur les parcours et valeurs observés, et non sur toutes les combinaisons possibles de permissions, données et erreurs réseau.
