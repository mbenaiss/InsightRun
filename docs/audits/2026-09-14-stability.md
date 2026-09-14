# Audit de stabilité — 14 septembre 2026

La PR #100 corrige une répétition réelle des notifications du dimanche, mais elle ne suffit pas à résoudre les problèmes observés. L’audit a permis de reproduire et de corriger plusieurs défauts dans les notifications, Strava, l’indexation et le chat IA. Les corrections incluent la PR #100. Une passe supplémentaire de performance prépare la version iOS 2.0.8.

## Périmètre et état du travail

- Base : `origin/main` au commit `242bb91`, plus le contenu de la [PR #100](https://github.com/mbenaiss/InsightRun/pull/100), commit `c00b9cf7a31a01ed1b4ef147449a1545737656c2`.
- Branche locale : `codex/stability-audit`.
- Dossier : `/Users/mbenaissa/go/src/github.com/mbenaiss/insightrun-stability-audit`.
- Le checkout original `insightrun` est resté propre. À la fin de la validation locale décrite ici, aucun déploiement n’avait encore été effectué. La livraison est désormais autorisée par l’utilisateur et passe par la PR #100 et les pipelines GitHub / Xcode Cloud.
- La version de développement iOS 2.0.8 contenant les corrections et optimisations a été compilée, installée et testée sur l’iPhone connecté. Les essais locaux précèdent le déploiement du backend corrigé.
- Lecture des chemins critiques iOS et backend, consultation de PostHog, tests automatiques, vérification du site public et de l’entrée de l’administration. Ce n’est pas une certification de chaque écran, appareil et scénario possible.

## Défauts corrigés

| Priorité | Problème et conséquence | Correction et preuve |
| --- | --- | --- |
| P1 | Le rafraîchissement Strava utilise `data.athlete.id`, alors que la réponse de rafraîchissement ne contient pas `athlete`. Le jeton peut tourner chez Strava avant que le serveur ne le sauvegarde ; les synchronisations suivantes échouent. | Une fonction commune conserve les métadonnées existantes et sauvegarde immédiatement les nouveaux jetons. Les chemins liste, détail, webhook et rafraîchissement l’utilisent. Reproduction par tests avec une réponse OAuth sans `athlete`. |
| P1 | Un résumé IA vide peut être enregistré dans les caches puis repris indéfiniment. La consolidation refuse ensuite les chaînes vides avec HTTP 400. | Rejet des réponses vides ou tronquées avant leur mise en cache, invalidation à la lecture des anciennes entrées vides, et reprise des lots locaux dont le résumé est vide. Tests avant/après sur les routes d’indexation. |
| P2 | La PR #100 limite la répétition hebdomadaire mais l’envoi immédiat ne respecte pas le réglage hebdomadaire et peut doubler le rappel récurrent. La désactivation globale ne persiste pas correctement après relancement. | Préférence globale persistante, respect du réglage hebdomadaire et de l’horaire, maintien du rappel récurrent comme envoi normal, verrou contre les appels concurrents. Un envoi de secours n’est autorisé que le dimanche après 18 h si le rappel manque, au plus une fois par semaine après succès. Sept tests couvrent refus, relancement, concurrence, doublons et reprise après erreur. |
| P2 | Une erreur du fournisseur IA, une réponse vide ou une connexion interrompue peut être interprétée comme un chat terminé avec succès. | Le backend émet une erreur SSE pour les réponses invalides/incomplètes et ne débite pas le quota de succès dans ces cas. Le client vérifie les événements et le marqueur de fin, puis annule la tâche réseau à la fermeture du flux. Tests backend et Swift. |
| P2 | Des pannes temporaires de rafraîchissement Strava provoquent une déconnexion ou sont présentées comme des erreurs internes indifférenciées. | Distinction entre reconnexion nécessaire (401), limitation Strava (429) et panne amont (502). Le client ne purge plus les jetons lors d’une simple panne réseau ou serveur. |
| P2 | Le contrôle CI appelé « Type check » n’exécute pas TypeScript ; des fichiers de tests iOS présents dans le dépôt ne sont pas rattachés à la cible. | `tsc --noEmit` réel, ajout des tests et du build Worker à la CI, vérification de format sans modification des fichiers, job de build/lint de l’administration. Rattachement de trois fichiers de tests iOS oubliés. Les fixtures de trois anciens tests sont alignées sur la validation de réponse déjà présente en production. |
| P1 | Next.js et l’adaptateur Cloudflare sont anciens ; l’audit des dépendances signale des versions touchées par des avis de sécurité. Hono et Wrangler sont également concernés. | Next.js `15.5.25`, OpenNext Cloudflare `1.20.6`, Hono `4.13.7` et Wrangler `4.131.1`, sans changement de version majeure. Builds Next.js, OpenNext et Worker validés. Des alertes transitives web restent ouvertes, voir ci-dessous. |

La nouvelle implémentation conserve les événements analytiques de la PR #100 et le suivi des rafraîchissements Strava. La route de rafraîchissement exige aussi la correspondance du jeton fourni : connaître un identifiant utilisateur ne suffit pas à récupérer les jetons du serveur.

Le comportement des notifications hebdomadaires est volontairement précisé : le rappel récurrent du dimanche à 18 h est conservé. L’ouverture de l’app ne remplace plus systématiquement ce rappel par une notification immédiate avec statistiques.

Fichiers principaux :

- `InsightRun/insightrun/Services/NotificationManager.swift`
- `InsightRun/insightrun/Services/BackendAPIClient.swift`
- `InsightRun/insightrun/Services/BatchIndexationManager.swift`
- `InsightRun/insightrun/Services/Strava/StravaAuthService.swift`
- `backend/src/routes/strava.ts`
- `backend/src/routes/analyzeHistory.ts`
- `backend/src/routes/agentChat.ts`
- `.github/workflows/build.yml`

## Ce que montre PostHog

Lecture du projet 96185, fenêtre des 14 jours précédant la consultation du 14 septembre, avant les parcours de validation de cet audit. L’échantillon est réduit : 24 utilisateurs distincts pour 196 événements `app_opened`.

| Signal | Observation |
| --- | --- |
| `strava_sync_failed` | 8 événements, 2 utilisateurs : 7 erreurs HTTP 500 et 1 erreur réseau. |
| `strava_activities_failed_backend` | 5 événements, 1 utilisateur, avec le message d’échec de rafraîchissement Strava. Ils ne sont pas à additionner aux erreurs client comme des incidents indépendants. |
| `indexation_failed` | 7 événements, 1 utilisateur : 3 HTTP 400, 1 accès HealthKit protégé, 1 annulation, 1 timeout et 1 connexion hors ligne. |
| `indexation_backend_rejected` | 3 événements sur `consolidate`, avec `batchSummaries.0` et `.1` vides. Cela confirme précisément la cause des rejets HTTP 400 analysés. |
| IA et génération | Un événement `ai_response_error` et un `workout_generation_failed` associés à une perte de connexion. |
| Crash/exception | Aucun événement correspondant trouvé dans cette fenêtre. L’instrumentation des crashes est récente : cela ne permet pas d’affirmer que tous les utilisateurs sont exempts de crash. |

Le défaut Strava reproduit par les tests est cohérent avec les erreurs de production, mais PostHog ne fournit pas à lui seul la preuve que chacun des sept HTTP 500 a exactement cette cause.

### Vérification de l’alerte Strava du 13 septembre

Nouvelle consultation le 14 septembre vers 07:59 UTC, après réception de l’alerte par l’utilisateur :

- Fenêtre du 13 septembre 15:58–16:18 UTC : **5 événements** `strava_activities_failed_backend`, pour **un seul utilisateur**, entre 16:00:27 et 16:01:44 UTC. Il ne s’agit donc pas d’un seul événement dans PostHog, ni de cinq utilisateurs touchés.
- Entre 16:18 et 18:18 UTC : aucun nouvel événement Strava enregistré. L’absence d’échec ne constitue pas une preuve de synchronisation réussie : aucun succès Strava n’est enregistré dans cette fenêtre non plus.
- Le 14 septembre à 07:47:20 UTC : même erreur pour **le même utilisateur**, pendant la période des essais sur l’iPhone. Cela montre une récurrence ; la version iOS de test utilise toujours le backend de production non corrigé.
- Le code serveur antérieur remplace aussi bien une erreur HTTP OAuth qu’une exception de lecture de `athlete` par le même message générique. La propriété `strava_status` est vide dans ces événements. Ils ne permettent pas de distinguer avec certitude une révocation de jeton, une panne amont et le défaut de sauvegarde reproduit localement.

Les données consultées ne montrent pas d’extension à d’autres utilisateurs depuis cette alerte. La priorité reste de publier le correctif serveur validé, puis de reconnecter Strava si le jeton déjà perdu ou révoqué ne peut plus être renouvelé. Aucun déploiement n’a été effectué lors de cette vérification.

## Validation réalisée

| Contrôle | Résultat |
| --- | --- |
| iOS : compilation et tests sur simulateur | **106 tests réussis**, zéro échec, zéro test ignoré : 82 tests de la cible principale, 20 tests d’analyse et 4 tests UI d’activation/consentement/reprise après erreur. |
| iPhone physique | **2 parcours UI réussis** : tableau de bord, entraînements, statistiques après chargement, progression, objectifs, réglages et détail d’une course avec son analyse déjà en cache. Captures inspectées. |
| Backend | **33 tests réussis**, lint/format Biome, `tsc --noEmit` et build Wrangler en `--dry-run` réussis. |
| Site public | Installation avec lockfile figé, lint, build Next.js et build OpenNext réussis. Accueil, support, confidentialité et conditions vérifiés dans le navigateur. |
| Administration | Installation avec lockfile figé, lint, build Next.js et build OpenNext réussis. La route `/dashboard` redirige vers le formulaire de connexion en l’absence de session. Aucun changement administrateur effectué. |
| Workflow | YAML analysé avec succès ; les commandes de validation ajoutées ont été exécutées localement. Le workflow GitHub lui-même n’a pas été lancé sur une PR distante. |
| Swift | `swift-format lint` exécuté. Les règles par défaut produisent de nombreux avertissements de style, notamment l’indentation à deux espaces face au code à quatre espaces. Ce n’est pas un lint sans avertissement ; aucune remise en forme globale n’a été appliquée. |
| Diff | `git diff --check` réussi. |

Un des nouveaux tests de notifications provoquait un arrêt dans le runtime de désallocation `@MainActor` de Xcode beta lorsqu’il était exécuté de façon synchrone. Le test s’exécute désormais dans un contexte asynchrone. La suite complète a ensuite été relancée avec succès ; aucun contournement n’a été ajouté au code de production pour ce problème de test.

Les scripts temporaires de parcours sur l’iPhone ont été retirés du dépôt : ils dépendent de données et de libellés présents sur cet appareil. Les tests de régression unitaires restent dans le projet.

## Performance sur l’iPhone

- Les statistiques évitent les requêtes HealthKit de scores d’effort, absents de cet écran : jusqu’à deux requêtes en moins par course de l’historique. Leurs graphiques restent visibles pendant un rafraîchissement ; une seconde demande concurrente sur le même modèle est ignorée.
- Au démarrage, le contexte du coach récupère au plus dix courses et diffère leurs mesures détaillées jusqu’à l’ouverture du coach. L’ouverture du coach charge bien les détails manquants avant d’afficher la conversation.
- Même parcours automatisé, trois lancements avant et après : médiane **5,81 s avant**, **3,59 s après**, puis **3,46 s** sur la vérification finale de 2.0.8. La réduction observée est d’environ **40 %** sur ce parcours. XCTest inclut ses délais de pilotage et de synchronisation ; ces temps ne sont pas une mesure isolée du rendu, ni un résultat garanti sur d’autres appareils ou historiques.
- Deux contrôles physiques supplémentaires passent : ouverture/fermeture du coach avec chargement différé, et affichage des statistiques sur trois relancements. Le script propre aux données de cet iPhone est conservé hors dépôt.

## Points restant ouverts

1. **Dépendances transitives du web.** Après les mises à jour ciblées, `bun audit` ne remonte plus aucune alerte dans le backend. Il reste 51 entrées d’alerte dans le site public (dont une critique portant sur `tar`) et 34 dans l’administration. Ces nombres incluent des dépendances d’outillage et plusieurs avis pour un même paquet ; ils ne représentent pas autant de failles exploitables dans l’application en production. Le tri des chemins réellement exposés et la mise à jour des dépendances transitives doivent encore être réalisés. Les avis portant sur Next.js, OpenNext, Hono et Wrangler ont disparu des résultats après mise à jour.
2. **Cohérence des zones cardiaques entre interface et IA.** Le détail de course calcule son pourcentage de FCmax à partir du maximum observé dans les entraînements, avec un repli à 190 (`WorkoutDetailView.swift`, `personalMaxHR`). Le contexte IA utilise une estimation liée à l’âge (`backend/src/prompts.ts`, `estimateIntensity`). Une divergence entre le texte IA en cache et la carte de mesures est visible sur le téléphone. Les deux calculs doivent être harmonisés avec une source explicite et une stratégie d’invalidation des analyses en cache. Aucun changement arbitraire de modèle physiologique n’a été appliqué dans cet audit de stabilité.
3. **Notifications en conditions réelles.** Les branches de calendrier et de concurrence sont testées, mais l’appareil n’a pas été laissé en observation jusqu’au dimanche suivant. L’événement `notification_sent` correspond à l’acceptation de la programmation par iOS, pas à une preuve de lecture ou de livraison effective.
4. **Couverture fonctionnelle restante.** Achat/restauration réelle, réinstallation avec migration de données, gros imports FIT, longue période hors ligne, refus de toutes les permissions et export réel vers une Apple Watch n’ont pas été exercés de bout en bout sur cet iPhone. Les tests de génération/export des modèles d’entraînement passent, ce qui ne remplace pas un transfert sur une montre.
5. **Petite anomalie web.** L’administration ne fournit pas de `favicon.ico` : le navigateur journalise un 404. Le formulaire et la redirection fonctionnent ; ce défaut n’est pas bloquant.

## Mise en service des corrections

La livraison prévue utilise la PR #100 complétée, les trois déploiements Cloudflare (backend, site et administration), puis une archive Xcode Cloud de la version iOS 2.0.8 pour soumission à Apple. Les statuts de livraison doivent être vérifiés dans ces services après fusion. Les jetons Strava déjà invalidés par une rotation perdue peuvent nécessiter une reconnexion ; la correction empêche la répétition du défaut mais ne recrée pas un jeton perdu.

Les requêtes PostHog agrégées, logs de builds, résultats XCTest et captures restent dans `/tmp/insightrun-stability-audit`. Les captures contiennent des données personnelles de santé et ne sont pas incluses dans le dépôt.

## Références techniques

- [Strava : rafraîchissement et rotation des jetons](https://developers.strava.com/docs/authentication/) — la réponse de rafraîchissement contient les jetons et leur expiration ; conserver le dernier jeton retourné.
- [Next.js : mise à jour de sécurité RSC](https://nextjs.org/blog/security-update-2025-12-11) — recommande une version corrigée de la branche utilisée.
- [Hono : avis sur le traitement CORS](https://github.com/honojs/hono/security/advisories/GHSA-8j4g-w8fx-2239).
- [OpenNext Cloudflare : avis et correctif de normalisation de chemin](https://github.com/opennextjs/opennextjs-cloudflare/security/advisories/GHSA-c7mq-gh6q-6q7c) — l’avis indique également une mitigation appliquée par Cloudflare ; la mise à jour de l’adaptateur reste recommandée.
