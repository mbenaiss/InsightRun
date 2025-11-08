# PostHog Funnels - Recommandations après PR #38

## 🆕 Nouveaux Événements Ajoutés

### Événements Banner d'Indexation
- `indexation_banner_shown` - Banner affiché dans l'AI Assistant
- `indexation_banner_sync_tapped` - Utilisateur clique "Synchroniser"
- `indexation_banner_dismissed` - Utilisateur clique "Plus tard"

### Événement AI sans Contexte
- `ai_message_sent_without_context` - Message AI envoyé sans historical summary
  - Propriété: `context_type` (workout/recovery)

---

## 📊 Funnels à Créer/Mettre à Jour

### 1. **Funnel: Onboarding Indexation** ⭐ PRIORITAIRE
**Objectif**: Mesurer le taux de conversion de la première découverte à l'indexation complète

```
Étape 1: ai_chat_opened
  └─ Filtre: is_first_launch = true OU première fois sans summary
Étape 2: indexation_banner_shown
Étape 3: indexation_banner_sync_tapped
Étape 4: indexation_started
Étape 5: indexation_completed
```

**KPI cible**: > 60% completion rate
**Insight**: Identifier où les nouveaux utilisateurs drop

---

### 2. **Funnel: AI Engagement sans Contexte**
**Objectif**: Comprendre l'usage de l'AI avant indexation

```
Étape 1: ai_chat_opened
Étape 2: indexation_banner_shown
Étape 3: indexation_banner_dismissed
Étape 4: ai_message_sent_without_context (repeated)
```

**Segment à créer**: "Never Indexed Users"
- Condition: `indexation_banner_dismissed` count > 2
- Sans `indexation_completed` dans les 30 derniers jours

**Action**: Campagne re-engagement ou amélioration du messaging

---

### 3. **Funnel: Retry après Échec**
**Objectif**: Mesurer la résilience des utilisateurs face aux erreurs

```
Étape 1: indexation_started
Étape 2: indexation_failed
Étape 3: indexation_retry_tapped
Étape 4: indexation_completed
```

**KPI cible**: > 40% retry rate
**Insight**: Qualité des messages d'erreur

---

### 4. **Funnel: Réindexation Récurrente**
**Objectif**: Mesurer l'adoption de la réindexation pour mise à jour du profil

```
Étape 1: indexation_completed (première fois)
  └─ Propriété: workouts_count < 50
Étape 2: [30 jours après]
Étape 3: indexation_banner_shown (pour refresh)
Étape 4: indexation_completed (deuxième fois)
  └─ Propriété: workouts_count >= 50
```

**KPI cible**: > 25% des utilisateurs réindexent dans les 3 mois

---

## 🎯 Dashboards Recommandés

### Dashboard: "Indexation Health"

#### Graphiques à inclure:

1. **Conversion Rate Timeline**
   - Metric: `indexation_banner_sync_tapped / indexation_banner_shown`
   - Par jour (7 derniers jours)

2. **Dismissal Rate**
   - Metric: `indexation_banner_dismissed / indexation_banner_shown`
   - Alert si > 50%

3. **Time to First Indexation**
   - Event: `ai_chat_opened` → `indexation_completed`
   - Median & P95
   - Objectif: < 5 minutes (median)

4. **AI Usage sans Contexte**
   - Metric: `ai_message_sent_without_context / ai_message_sent`
   - Par contexte (workout vs recovery)
   - Objectif: < 20% après 1 mois

5. **Indexation Failure Rate**
   - Metric: `indexation_failed / indexation_started`
   - Par batch_number (identifier les batches problématiques)
   - Alert si > 5%

6. **Banner Dismissal Cohort**
   - Users qui dismissent 1 fois, 2 fois, 3+ fois
   - Conversion finale vers indexation

---

## 🔍 Cohorts à Créer

### 1. **Never Indexed Power Users**
**Définition**:
- `ai_message_sent` count > 10
- `indexation_completed` count = 0
- `indexation_banner_dismissed` count > 2

**Action**: Email personnalisé expliquant la valeur de l'indexation

---

### 2. **Successful First-Time Indexers**
**Définition**:
- `indexation_completed` count = 1
- Time between `ai_chat_opened` and `indexation_completed` < 10 min

**Action**: Feedback survey + App Store review request

---

### 3. **Indexation Abandoners**
**Définition**:
- `indexation_started` count > 0
- `indexation_completed` count = 0
- Last event = `indexation_cancelled` OU `indexation_failed`

**Action**: Notification push "Terminez votre profil athlétique"

---

### 4. **Re-indexation Eligible**
**Définition**:
- `indexation_completed` count >= 1
- Last `indexation_completed` > 90 days ago
- `ai_message_sent` count > 5 (dans les 30 derniers jours)

**Action**: Banner automatique "Mettez à jour votre profil"

---

## 🚨 Alertes à Configurer

### Alert 1: Banner Dismissal Spike
```
Condition: (indexation_banner_dismissed / indexation_banner_shown) > 60%
Timeframe: 1 jour
Notification: Slack #alerts-product
```

### Alert 2: Indexation Failure Rate
```
Condition: (indexation_failed / indexation_started) > 10%
Timeframe: 1 heure
Notification: Slack #alerts-engineering
```

### Alert 3: Never Indexed Growing Segment
```
Condition: Cohort "Never Indexed Power Users" > 100 utilisateurs
Timeframe: Weekly check
Notification: Email product team
```

---

## 📋 Actions Immédiates

### À faire dans PostHog:

1. ✅ **Créer le funnel "Onboarding Indexation"** (priorité haute)
2. ✅ **Créer les 4 cohorts définis ci-dessus**
3. ✅ **Créer le dashboard "Indexation Health"**
4. ✅ **Configurer les 3 alertes**
5. ⚠️ **Vérifier que les événements remontent correctement** (après déploiement)

### Suivi post-déploiement (J+7):

- [ ] Analyser le taux de conversion du banner
- [ ] Identifier les messages d'erreur les plus fréquents (via `indexation_failed` properties)
- [ ] Comparer l'engagement AI avec vs sans historical summary
- [ ] Mesurer le churn rate entre les 2 segments

---

## 💡 Hypothèses à Tester

### H1: Le banner améliore l'adoption de l'indexation
**Baseline**: Sans banner, taux d'indexation organique
**Test**: Avec banner, mesurer `indexation_banner_sync_tapped / indexation_banner_shown`
**Succès**: > 50% conversion rate

### H2: Les utilisateurs avec historical summary sont plus engagés
**Métrique 1**: `ai_message_sent` count (avec vs sans summary)
**Métrique 2**: Session duration dans l'AI Assistant
**Métrique 3**: Retention D7, D30
**Succès**: +20% engagement avec summary

### H3: Le messaging "Plus tard" n'est pas optimal
**Test A/B futur**:
- Variante A: "Plus tard" (actuel)
- Variante B: "Utiliser sans historique"
- Variante C: "Me le rappeler demain"
**Métrique**: Taux de conversion finale vers indexation

---

## 🔗 Liens Utiles

- [PostHog Funnels Documentation](https://posthog.com/docs/user-guides/funnels)
- [PostHog Cohorts Documentation](https://posthog.com/docs/user-guides/cohorts)
- [PostHog Alerts Documentation](https://posthog.com/docs/user-guides/alerts)

---

**Date de création**: 2025-01-08
**PR associée**: #38 - Fix indexation issues and add banner integration
**Auteur**: Claude Code
