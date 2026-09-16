# Vérification des objectifs et plans — 16 septembre 2026

La génération a été vérifiée sur l’iPhone connecté avec l’API de production : **50,5 secondes**, plan de **18 semaines et 71 séances**, retrouvé après fermeture et relancement de l’app. L’objectif temporaire et les objectifs QA restants de ce passage ont été supprimés. Le nombre de séances tient compte de la dernière semaine partielle : aucune séance n’est programmée après la course.

## Correctifs

- Calendrier inclusif : une course exactement quatre semaines après le départ appartient à la cinquième semaine du calendrier. Elle ne se retrouve plus une semaine trop tôt. Les dates envoyées par le nouvel iOS sont des jours calendaires, indépendants du décalage UTC et des changements d’heure.
- Les préparations lointaines commencent au plus tôt 167 jours avant la course, afin de respecter le plafond de 24 semaines et de conserver la vraie date de compétition. Le fuseau du calendrier est enregistré avec le plan.
- Refus des profils sans jour sélectionné, des jours invalides ou incohérents, des niveaux inconnus, des chronos invalides et des préparations trop courtes. Une réponse partielle est rejetée par iOS.
- Le niveau choisi manuellement n’est plus écrasé par une réponse HealthKit tardive.
- Une seule génération ou adaptation à la fois. Une réponse tardive ne recrée pas un objectif supprimé et n’écrase pas une séance modifiée entre-temps. Les erreurs concernent le bon objectif.
- Régénération avec confirmation ; l’ancien plan est conservé si la tentative échoue. Le changement de début recalcule le plan pour garder la date de course et est indisponible lorsque des séances ont déjà été validées.
- Les adaptations préservent les semaines précédentes et la semaine courante, contrôlent les numéros de semaines et retirent les séances placées après la compétition.
- La séance du jour respecte les déplacements, y compris entre semaines, et exclut les séances sautées.
- La conversion WorkoutKit accepte les séances sans étapes détaillées en utilisant leur distance, durée ou objectif libre. L’export utilise la date de la séance ; une séance passée reste disponible aujourd’hui.
- Une génération réussie décompte une requête gratuite. Une erreur, une annulation ou une réponse incomplète ne la décompte pas.
- L’import de plusieurs séances conserve toutes les associations précédentes ; les séances sautées ne sont pas validées automatiquement et les activités trop courtes ne correspondent plus à une séance par défaut lorsqu’un critère manque.

Les changements précédemment demandés sur les entraînements sont conservés : uniquement les courses à pied Strava, filtres de distance, renommage des séances et année dans les dates. L’onglet Objectifs ne présente plus l’historique des courses saisies manuellement ni l’option d’ajouter une course passée.

## Scénarios et preuves

| Scénario | Vérification |
|---|---|
| 5 km, 10 km, semi, marathon, ultra ; trois niveaux ; 1 à 7 jours choisis | 105 combinaisons contrôlées dans les tests iOS ; transmission du profil vérifiée côté backend |
| Chrono et contrainte/blessure | Contenu de la requête iOS et des prompts backend vérifié |
| Aucun jour sélectionné ; sélection manuelle du niveau | Test UI permanent : bouton Suivant désactivé puis réactivé, récapitulatif et suppression de l’objectif |
| Création, génération et conservation du plan | Parcours réel sur iPhone ; fermeture, relancement et nettoyage réussis |
| Renommage, régénération, démarrage aujourd’hui | Tests du modèle et parcours UI avec réponses contrôlées |
| Objectifs multiples, suppression, état vide | Tests du modèle, du stockage et parcours sur simulateur |
| Timeout, absence de réseau, quota HTTP 429, réponse partielle | Erreur affichée, objectif conservé et nouvelle tentative possible ; injection locale des erreurs |
| Passage en arrière-plan | Génération contrôlée lente, retour au premier plan et plan disponible |
| Refus puis acceptation du consentement depuis Objectifs | Parcours UI réussi sur simulateur hors mode démo |
| Abonnement requis | Vérification de la restriction dans le modèle ; parcours UI du paywall en cours de finalisation |
| Annulation, double demande, suppression pendant génération, modification pendant adaptation | Tests de concurrence et de préservation des données |
| Terminer/annuler, sauter/restaurer, déplacer/rétablir une séance | Parcours UI précédents, régressions sur les dates effectives et le rapprochement HealthKit |
| Dates limites, plafond, changements d’heure | Bornes 27, 28, 29, 120, 167, 168 et 365 jours ; calculs et persistance testés pour Paris, New York et Auckland, en mars et octobre |
| Export d’une séance du plan | Conversion WorkoutKit, intervalles, répétitions, tapis et date d’export testés ; transfert physique vers la montre non testé, conformément au choix de continuer sans elle |

Les 105 combinaisons utilisent des réponses déterministes : ce ne sont pas 105 appels LLM réels. Les tests de dates portent sur les calculs du calendrier et sa persistance, pas sur un changement manuel de fuseau dans les réglages de l’iPhone. Aucun achat réel n’est effectué pendant les tests d’abonnement.

## Validation exécutée

- Backend : **119 tests réussis, 422 assertions**, vérification TypeScript, lint et build réussis.
- Suite iOS complète : **175 tests réussis, 1 test live optionnel ignoré**, aucun échec. Elle inclut les captures des écrans clairs/sombres et les parcours d’activation.
- Après les dernières corrections : **166 tests unitaires iOS réussis**, puis le nouveau test UI du formulaire réussi.
- Deux tests UI externes réussis pour la reprise après erreurs, l’arrière-plan, le renommage, la régénération et la sélection des jours.
- Build iPhone réussi ; version de développement installée et testée sur l’appareil. Cela ne constitue pas une nouvelle publication App Store.
- Lint Swift exécuté : aucune augmentation des alertes par fichier modifié ; le ViewModel et les nouveaux tests sont sans alerte. Les alertes de format déjà présentes ailleurs ne sont pas masquées.

## Correctif du timeout déjà livré

La PR [#111](https://github.com/mbenaiss/InsightRun/pull/111), fusionnée à 12:15 UTC, a été déployée à 12:15:34 UTC, version Cloudflare `9434487a-3e82-44e7-b4e7-14b131c1a7bb`.

Elle génère et adapte les plans par blocs de quatre semaines, avec une tentative de secours, un budget total de 150 secondes et une validation des réponses. Le délai iOS est de 185 secondes. Mesures réelles après ce correctif : génération API de 18 semaines en 49,6 secondes ; adaptation de 17 semaines en 100,5 secondes. Ces mesures ponctuelles ne garantissent pas une latence constante.

## Artefacts locaux

- Campagne complémentaire : `/tmp/insightrun-objectives-audit-2026-09-16/`.
- Suite complète : `full-unit.xcresult` ; derniers tests unitaires : `final-unit.xcresult` ; formulaire : `wizard-regression.xcresult`.
- Parcours UI contrôlés : `ui-recovery-final.xcresult` ; consentement : premier test réussi dans `ui-permissions-v5.xcresult`.
- iPhone réel : `iphone-final.xcresult`, génération à 50,548 secondes, persistance et nettoyage réussis.
- Première campagne : `/tmp/insightrun-plan-audit-2026-09-16/`.
- Capture réelle : `/Users/mbenaissa/.codex/visualizations/2026/09/14/01a09ec6-1843-71d3-a59a-51917c57b66c/training-plans-2026-09-16/objectifs-verifies-iphone.png`.
