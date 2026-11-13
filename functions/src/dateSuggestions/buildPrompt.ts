import type { DateCriteriaPayload } from "./types";

export interface RatingHistoryEntry {
  title: string;
  stars: number;
  tags: string[];
  comment: string | null;
}

// Keep in sync with BudgetLevel.priceRange in the iOS app: these are the amounts shown to the user.
const budgetLabel: Record<string, string> = {
  guenstig: "günstig (bis ca. 20 € pro Person für den gesamten Plan inkl. Essen, Trinken und Eintritt)",
  mittel: "mittel (ca. 20–45 € pro Person für den gesamten Plan inkl. Essen, Trinken und Eintritt)",
  gehoben: "gehoben (ab ca. 45 € pro Person für den gesamten Plan inkl. Essen, Trinken und Eintritt)",
};

const mobilityLabel: Record<string, string> = {
  zufuss: "zu Fuß",
  oepnv: "ÖPNV",
  auto: "Auto",
};

const indoorOutdoorLabel: Record<string, string> = {
  drinnen: "drinnen",
  draussen: "draußen",
  egal: "egal (drinnen oder draußen)",
};

export function buildSystemPrompt(isFirstMeeting: boolean, planningMode: DateCriteriaPayload["planningMode"] = "date"): string {
  const safetyRule = isFirstMeeting
    ? `\n- Dies ist ein erstes Treffen zwischen zwei Menschen, die sich neu kennenlernen: Wähle ausschließlich öffentliche, gut besuchte und leicht erreichbare Orte. Keine Privatwohnungen, abgelegenen Orte, langen Autofahrten oder Vorschläge, die eine Person isolieren könnten. Beginne mit einer klaren öffentlichen ersten Station (z.B. Café, Museum, Restaurant oder belebter Park bei Tageslicht).`
    : "";

  const planLabel = planningMode === "group" ? "gemeinsames Gruppenerlebnis" : "Date";
  return `Du bist der Vorschlags-Assistent einer App für gemeinsame Erlebnisse. Deine Aufgabe: aus den gegebenen Kriterien fünf konkrete, umsetzbare Varianten für ein ${planLabel} erstellen.

Regeln:
- Jeder Vorschlag besteht aus exakt derselben Anzahl von zwei oder drei "Stationen" (z.B. Restaurant + anschließender Spaziergang). Die App zeigt pro Abschnitt fünf Alternativen; deshalb müssen Station 1, Station 2 und ggf. Station 3 in allen fünf Varianten jeweils funktional vergleichbar sein. Variiere für jeden Abschnitt die konkreten Orte und Aktivitäten deutlich.
- Formuliere jede Station als konkrete Aktivität an einem realen, öffentlich auffindbaren Ort in der angegebenen Stadt. "title" nennt Aktivität UND Ort, z.B. "Spaziergang zum Landgrafenschloss" oder "Tapas bei La Siesta". "searchQueryHint" enthält ausschließlich den möglichst exakten Ortsnamen plus Stadt, z.B. "Landgrafenschloss Marburg" oder "La Siesta Marburg". Die App prüft diesen Hinweis anschließend gegen Apple Maps und zeigt nur den tatsächlich gefundenen Ort samt Adresse an.
- Erfinde niemals eine Adresse, Öffnungszeiten, Telefonnummer, Website oder eine konkrete Veranstaltung. Wenn du bei einem Ort nicht sicher bist, wähle einen namentlich bekannten, öffentlich auffindbaren Ort oder ein konkretes Wahrzeichen in der Stadt. Verwende nie nur eine allgemeine Ortsart wie "Restaurant Marburg" oder "Park Marburg".
- Halte dich an Budget (die genannte Preisspanne pro Person gilt für den gesamten Plan), Stimmung, Anlass (falls angegeben), Mobilität/Radius und Ernährungspräferenzen aus den Kriterien.
- Ordne die Stationen so, dass sie räumlich sinnvoll zusammenpassen. Plane bei "zu Fuß" besonders kompakt und vermeide Ortswechsel, die einen großen Teil der gemeinsamen Zeit verbrauchen würden.
- Berücksichtige den konkreten Wochentag und die Startzeit. Wähle nur Orte, die zu dieser Zeit typischerweise geöffnet sind, behaupte aber niemals verifizierte Öffnungszeiten. Bei Gastronomie oder größeren Gruppen darf die Beschreibung knapp auf eine sinnvolle Reservierung hinweisen.
- "estimatedDurationMinutes" pro Station realistisch schätzen. Reserviere ungefähr 10–20 % der Gesamtdauer für Wege; die reine Stationszeit soll den restlichen Zeitrahmen sinnvoll ausfüllen.
- Bei Gruppen müssen alle Alternativen praktisch für die angegebene Personenzahl funktionieren. Vermeide enge Paar-Aktivitäten, spontane Kleinsttische und romantische Formulierungen.
- Alle Texte (title, summary, description, moodTags) auf Deutsch, charmant-augenzwinkernd im Ton, nie kitschig-übertrieben.
- Antworte ausschließlich über das bereitgestellte Tool submit_date_suggestions.${safetyRule}`;
}

export function buildUserContent(criteria: DateCriteriaPayload, ratingHistory: RatingHistoryEntry[], isFirstMeeting: boolean): string {
  const criteriaLines = [
    `Stadt: ${criteria.city}`,
    `Budget: ${budgetLabel[criteria.budget] ?? criteria.budget}`,
    `Stimmung: ${criteria.moods.length > 0 ? criteria.moods.join(", ") : "keine Präferenz"}`,
    `Drinnen/Draußen: ${indoorOutdoorLabel[criteria.indoorOutdoor] ?? criteria.indoorOutdoor}`,
    `Datum: ${criteria.date}, Uhrzeit: ${criteria.time}`,
    `Gewünschte Gesamtdauer: ca. ${criteria.durationMinutes} Minuten`,
    // A group meet-up has no "occasion" (spontanes Date / Jahrestag); the person only gives food wishes.
    ...(criteria.planningMode === "group" ? [] : [`Anlass: ${criteria.occasion}`]),
    `${criteria.planningMode === "group" ? "Essenswünsche und Ernährung der Runde" : "Ernährungspräferenzen"}: ${criteria.dietaryPreferences.length > 0 ? criteria.dietaryPreferences.join(", ") : "keine"}`,
    `Mobilität: ${mobilityLabel[criteria.mobility] ?? criteria.mobility}, Radius: ${criteria.radiusKm} km`,
    criteria.planningMode === "group"
      ? `Planart: Gruppentreffen für ${criteria.participantCount} Personen. Wähle ausdrücklich Orte und Aktivitäten, die für diese Gruppengröße funktionieren (Sitzplätze, Reservierbarkeit, gemeinsamer Rhythmus). Keine romantische Paar-Copy.`
      : "Planart: Date zu zweit."
  ].join("\n");

  const historyBlock = ratingHistory.length === 0
    ? "Noch keine bewerteten Dates vorhanden."
    : ratingHistory
      .map((entry) => {
        const tagsPart = entry.tags.length > 0 ? `, Tags: [${entry.tags.join(", ")}]` : "";
        const commentPart = entry.comment ? `, Kommentar: "${entry.comment}"` : "";
        return `- "${entry.title}", ${entry.stars} Sterne${tagsPart}${commentPart}`;
      })
      .join("\n");

  const historyTitle = isFirstMeeting
    ? "Bisher bewertete gemeinsame Dates dieses Matches (zur Personalisierung, neueste zuerst)"
    : "Bisher bewertete Dates dieses Paares (zur Personalisierung, neueste zuerst)";
  return `## Kriterien für das neue Date\n${criteriaLines}\n\n## ${historyTitle}\n${historyBlock}`;
}
