# Suivi des achats — 14 septembre 2026

La vérification PostHog de 12:52 UTC a trouvé 12 démarrages d’achat sur deux identifiants, avec les builds 340 et 342, sans résultat enregistré. Ce constat ne permet pas de conclure à douze paiements échoués : les erreurs et annulations des deux paywalls n’étaient pas reliées aux événements analytics.

## Correction

- Les paywalls de l’inscription et de l’app transmettent désormais les échecs d’achat, les annulations de tentative et les échecs de restauration.
- `subscription_purchase_cancelled` distingue une tentative annulée de `subscription_cancelled`, réservé à la résiliation d’un abonnement.
- `subscription_restore_failed` couvre les paywalls et la restauration depuis les réglages. L’erreur des réglages continue d’être propagée à son appelant.
- Les diagnostics portent l’origine, le produit lorsqu’il est connu, le code et le domaine de l’erreur, ainsi qu’un message limité à 500 caractères. Le dictionnaire `userInfo` complet n’est pas exporté.
- Les restaurations indiquent `has_active_subscription`, pour distinguer une restauration vide d’un abonnement retrouvé. Un callback d’achat réussi est enregistré même si aucun droit actif n’est encore présent, avec ce même indicateur.
- Les restrictions analytics existantes pour les builds internes, Debug, de démonstration et TestFlight restent appliquées.

## Validation

Validation locale réussie : 128 tests de régression iOS et 8 nouveaux tests ciblés du contrat des événements, exécutés en deux passes, sans échec ni test ignoré. Le build Release et la validation du projet Xcode réussissent. Le lint Swift ne signale aucune erreur ; les deux nouveaux fichiers ne produisent aucun avertissement. Les quatre fichiers Swift existants conservent des avertissements de mise en forme. `git diff --check` réussit.

Ces événements concernent les nouvelles tentatives effectuées avec le correctif. Ils ne permettent pas de reconstituer le résultat des douze anciennes tentatives. Les tests utilisent un collecteur local et n’injectent pas de faux achats dans PostHog.
