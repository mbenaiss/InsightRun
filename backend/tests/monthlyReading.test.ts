import { describe, expect, test } from 'bun:test'
import { rewriteMonthlyReadingQuestion } from '../src/monthlyReading'

const frenchQuestion = `Tu écris la « Lecture du mois » : un résumé d'une seule phrase, factuel, qui compare le mois en cours à la même durée écoulée du mois précédent.

CHIFFRES (utilise EXACTEMENT ces valeurs, ne recompte jamais depuis une liste de séances) :
- Mois en cours : 11 runs · 61.2 km · 6h50 · 6:42/km
            - Même durée du mois précédent : 1 runs · 5.0 km · 32min · 6:28/km

Règles strictes :
- Une seule phrase, 25 mots maximum, sans titre ni liste.`

const englishQuestion = `Write the "Read of the month": a single, factual sentence that compares the current month with the same elapsed portion of the previous month.

FIGURES (use these EXACT values, never recompute from a session list):
- Current month: 11 runs · 61.2 km · 6h50 · 6:42/km

Strict rules:
- One sentence only, 25 words max, no heading, no list.`

describe('monthly reading question rewrite', () => {
  test('keeps the French totals and asks for insight beyond the cards', () => {
    const rewritten = rewriteMonthlyReadingQuestion(frenchQuestion)
    expect(rewritten).toContain('- Mois en cours : 11 runs · 61.2 km · 6h50 · 6:42/km')
    expect(rewritten).toContain(
      '- Même durée du mois précédent : 1 runs · 5.0 km · 32min · 6:28/km'
    )
    expect(rewritten).toContain('2 à 3 phrases, 60 mots maximum')
    expect(rewritten).not.toContain('25 mots maximum')
  })

  test('rewrites the English question with its totals', () => {
    const rewritten = rewriteMonthlyReadingQuestion(englishQuestion)
    expect(rewritten).toContain('- Current month: 11 runs · 61.2 km · 6h50 · 6:42/km')
    expect(rewritten).toContain('2 to 3 sentences, 60 words max')
  })

  test('leaves other questions untouched', () => {
    expect(rewriteMonthlyReadingQuestion('How was my run today?')).toBe('How was my run today?')
    const withoutTotals = 'Tu écris la « Lecture du mois » sans chiffres.'
    expect(rewriteMonthlyReadingQuestion(withoutTotals)).toBe(withoutTotals)
  })
})
