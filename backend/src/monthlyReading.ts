// The iOS app (up to 2.0.12) sends the whole "Lecture du mois" prompt as the agent chat
// question. Rewriting it here improves the reading for every installed version.
const FRENCH_MARKER = 'Tu écris la « Lecture du mois »'
const ENGLISH_MARKER = 'Write the "Read of the month"'

function totalsLines(question: string, header: RegExp): string[] | null {
  const lines = question.split('\n')
  const start = lines.findIndex((line) => header.test(line))
  if (start === -1) return null
  const totals: string[] = []
  for (const line of lines.slice(start + 1)) {
    const trimmed = line.trim()
    if (!trimmed.startsWith('- ')) break
    totals.push(trimmed)
  }
  return totals.length > 0 ? totals : null
}

function frenchPrompt(totals: string[]): string {
  return `Tu écris la « Lecture du mois » d'un coach de course à pied. Le coureur voit déjà ces totaux sur ses cartes : ton rôle est d'expliquer ce qu'ils cachent.

TOTAUX (déjà affichés ; si tu en cites un, utilise EXACTEMENT ces valeurs) :
${totals.join('\n')}

Appuie-toi sur les séances du mois fournies dans le contexte :
- Comment le volume a été construit : régularité semaine après semaine, sortie la plus longue, part des séances faciles et intenses.
- Un point d'attention concret si les données le montrent, par exemple une hausse de volume très rapide par rapport au mois précédent ou une allure qui glisse sur les sorties faciles.
- Termine par une suggestion simple et réaliste pour la fin du mois.

Règles strictes :
- 2 à 3 phrases, 60 mots maximum, sans titre ni liste.
- Ne répète pas simplement les totaux : au plus une valeur des cartes, le reste doit venir des séances.
- Ton neutre et factuel. Pas d'emojis, pas d'exclamations, pas de superlatifs creux.
- N'invente rien et ne signale jamais une donnée manquante. Ne conclus pas qu'une allure plus rapide prouve une meilleure forme : parcours et types de séances peuvent différer.
- Écris les dates en langage naturel (le 21, la semaine dernière), jamais au format 2026-09-21.
- Réponds uniquement par le texte final, sans préambule ni guillemets.`
}

function englishPrompt(totals: string[]): string {
  return `Write a running coach's "Read of the month". The runner already sees these totals on their cards: your job is to explain what they hide.

TOTALS (already displayed; if you quote one, use these EXACT values):
${totals.join('\n')}

Use the month's sessions supplied in the context:
- How the volume was built: week-to-week consistency, longest run, share of easy and hard sessions.
- One concrete watch-out if the data shows it, e.g. a very fast volume increase versus the previous month or easy-run pace drifting.
- End with one simple, realistic suggestion for the rest of the month.

Strict rules:
- 2 to 3 sentences, 60 words max, no heading, no list.
- Do not just restate the totals: quote at most one card value; the rest must come from the sessions.
- Neutral, factual tone. No emojis, no exclamations, no empty superlatives.
- Do not invent anything and never flag missing data. Do not infer improved fitness from faster average pace: routes and workout types can differ.
- Write dates in natural language (on the 21st, last week), never as 2026-09-21.
- Answer with the final text only, no preamble, no surrounding quotes.`
}

export function rewriteMonthlyReadingQuestion(question: string): string {
  if (question.startsWith(FRENCH_MARKER)) {
    const totals = totalsLines(question, /^\s*CHIFFRES\b/)
    return totals ? frenchPrompt(totals) : question
  }
  if (question.startsWith(ENGLISH_MARKER)) {
    const totals = totalsLines(question, /^\s*FIGURES\b/)
    return totals ? englishPrompt(totals) : question
  }
  return question
}
