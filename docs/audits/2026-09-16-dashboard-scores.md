# Dashboard — audit des calculs, 16 septembre 2026

## Résultat

La disponibilité n’était pas cohérente entre le calcul local et le backend dans plusieurs cas reproductibles. Les corrections alignent les entrées, les références personnelles et les règles de repli. Les autres scores utilisent les barèmes existants ; les corrections portent sur les données absentes, les bornes et les explications affichées.

Cet audit vérifie le calcul logiciel et sa cohérence avec les données transmises. Il ne valide pas médicalement les pondérations, les seuils ou la capacité des scores à prédire une blessure ou une performance.

## Corrections

| Élément | Problème constaté | Correction |
| --- | --- | --- |
| Disponibilité : SpO₂ | La saturation était affichée mais absente des données envoyées au backend, malgré son poids nominal de 10 %. | Ajout dans le modèle partagé par la disponibilité et les analyses. |
| Disponibilité : précision | VFC, fréquence cardiaque au repos, respiration et efficacité du sommeil étaient tronquées avant envoi. | Conservation des décimales jusqu’au calcul final. |
| Disponibilité : sommeil | iOS utilisait les références personnelles de sommeil profond et paradoxal ; le backend utilisait des plages fixes. Les phases absentes étaient également traitées différemment. | Transmission des références personnelles, même calcul des phases et même contribution neutre lorsque les phases manquent. |
| Disponibilité : références incomplètes | Une référence absente ou un écart-type nul pouvait donner un résultat différent selon la plateforme. | Plages fixes lorsque la référence manque ; coefficient de variation lorsque l’écart-type est nul. |
| Disponibilité : absence de mesures | Un objet de récupération vide pouvait produire 50/100. | Aucun appel côté iOS sans mesure pertinente ; réponse 422 avant coaching côté serveur. Les entrées numériques invalides sont rejetées. |
| Disponibilité : statut et cache | Un statut fourni par le client pouvait contredire son score figé. | Statut dérivé du score. Version des entrées de récupération renouvelée pour recalculer le score courant avec les nouvelles données. |
| Disponibilité : efforts récents | Seules les trois dernières courses étaient chargées, alors que la pénalité peut couvrir sept jours. | Chargement des courses des huit derniers jours, puis application des fenêtres prévues par le backend. La pénalité maximale est appliquée une seule fois. |
| Sommeil | En l’absence de nuit pour la journée choisie, une ancienne nuit sans aucun chevauchement pouvait être sélectionnée. | Exclusion des sessions hors journée et des sessions sans sommeil ; regroupement linéaire des échantillons, y compris lorsque leurs intervalles se chevauchent. |
| Sommeil : anciens clients | La version 2.0.8 peut envoyer une durée de sommeil nulle lorsque seuls du temps au lit ou des éveils sont enregistrés. | Le serveur traite une durée nulle comme une absence de sommeil et conserve les autres signaux. Les durées négatives ou non finies restent rejetées. |
| Sommeil : sources contradictoires | Des phases fusionnées séparément peuvent dépasser la durée totale de sommeil. Un rejet strict aurait bloqué aussi les anciens clients. | Si la somme des phases dépasse le total, seules les phases sont écartées ; durée, efficacité et autres signaux restent disponibles. Le serveur accepte aussi les anciens payloads et utilise le même repli neutre. |
| Sommeil : explication | La fiche annonçait une pondération durée/efficacité/phases absente du calcul du score de sommeil. | Affichage du vrai barème : base de 50 points, bonus/malus de durée, bonus d’efficacité. Les phases sont distinctes de ce score. |
| Effort | Les objectifs invalides pouvaient provoquer une division invalide. | Objectifs de repli 400 kcal et 30 min ; contributions finies bornées entre 0 et 100 %. |
| Charge cardiaque | Le score principal et sa tendance répétaient leur normalisation. | Fonction commune et contrôles numériques du TRIMP et de la normalisation. |
| Fraîcheur | La courbe pouvait contenir une valeur lorsque la charge chronique était insuffisante pour afficher le score principal. | Même seuil de charge chronique pour le score et sa courbe. |
| Mode démonstration | Des textes de coaching utilisaient des chiffres fixes différents des cards. | Utilisation du score et du total de calories réellement affichés. |
| Bilan hebdomadaire | Les jours vides pouvaient apporter 50 points à la moyenne ; une semaine vide affichait 0. | Exclusion des jours vides, moyenne absente affichée « — », absence de faux score dans le coaching. Invalidation des anciens résumés mis en cache. |

## Contrôles chiffrés

- Douze scénarios JSON communs sont exécutés par les tests Swift et TypeScript : références complètes, phases absentes, références de phases absentes, écart-type nul, référence partielle, absence de référence, mode sans sommeil, nuit très courte, combinaison VFC basse/nuit courte saturation seule phases contradictoires entre sources Santé et ancien enregistrement de sommeil de durée nulle.
- Exemple synthétique avec toutes les mesures et références personnelles : **61/100** attendu et calculé des deux côtés après correction. L’ancien backend donnait **69/100** avec ces mêmes références parce qu’il ignorait celles des phases de sommeil. Cet exemple n’est pas une mesure personnelle de l’utilisateur.
- Exemple de conflit : 8 h de sommeil total avec 6 h de profond et 6 h de paradoxal transmises par un ancien client. La route répond 200 et conserve **61/100** pour le scénario de référence ; les phases incohérentes ne participent plus au calcul.
- Sommeil : 8 h avec 90 % d’efficacité donnent **100/100** ; 6,5 h avec 80 % donnent **80/100** ; 4 h avec 80 % donnent **45/100** ; 10 h avec 90 % donnent **75/100**. Ce sont les résultats du barème existant, conservé sans retouche des seuils.
- Effort : 5 000 pas, 200 kcal et 15 minutes, avec les objectifs de repli, donnent **50/100**.
- TRIMP : 45 minutes à 150 bpm, repos 50 bpm, maximum 190 bpm donnent **81,0715195052** avec les coefficients masculins et **91,1242997930** avec les coefficients féminins existants.
- Charge cardiaque : ATL 44,6 et CTL 26,6 donnent **16/20**. Avec les mêmes charges, la fraîcheur vaut **28/100**.
- Les poids nominaux de disponibilité restent sommeil 40 %, VFC 25 %, repos 15 %, SpO₂ 10 %, respiration 10 %. Ils sont renormalisés sur les signaux présents. La fiche l’explique désormais. Une mesure isolée peut donc peser 100 % du résultat : le score ne constitue pas à lui seul un indicateur de complétude des données.
- Le score de disponibilité peut différer de la moyenne de récupération du bilan : le backend peut appliquer une pénalité d’effort récent et conserver le score matinal. Les douze scénarios de parité vérifient le calcul de base ; les pénalités et le score figé sont testés séparément.

## Validation et livraison

- **217 tests sur simulateur réussis, 0 échec, 0 ignoré**, après intégration de Statistiques depuis `main` et des cas de compatibilité anciens clients. Suites principales, analyses, activation, neuf cards Dashboard, bilan, calendrier et navigation Statistiques. iPhone 17 Pro simulé sous iOS 26.2, application 2.0.9 / build 345.
- **148 tests backend réussis**, dont les douze scénarios partagés ; vérification TypeScript, lint Biome, format et compilation Worker en mode `--dry-run` réussis.
- Les captures du simulateur ont été inspectées ; le coaching de démonstration des calories correspond désormais au total et à la répartition affichés.
- Builds Debug et Release sur simulateur réussis après les dernières corrections.
- Lint Swift exécuté sur les 27 fichiers Swift modifiés : aucune erreur, avertissements de style avec la configuration par défaut. `git diff --check` passe.
- Les tests finaux utilisent le simulateur à la demande de l’utilisateur. Les mesures de performance et les cinq parcours iPhone de la première phase restent documentés dans l’audit des rafraîchissements ; ils ne constituent pas une validation du nouveau backend en production.

Résultats locaux : `/tmp/insightrun-scores-2026-09-16/final-209.xcresult` et journaux du même dossier.

Les corrections du backend doivent être déployées pour que le service en ligne applique le même calcul. Aucun déploiement backend de production ni envoi à Apple n’est réalisé par cet audit. Les scores historiques enregistrés ne sont pas réécrits rétroactivement.
