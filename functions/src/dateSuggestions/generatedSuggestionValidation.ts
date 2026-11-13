import type { BudgetLevel, RawStation, RawSuggestion, StationCategory } from "./types";

/**
 * Runtime guard for the model boundary. Tool schemas guarantee JSON shape, but not useful
 * content: without this guard a model can still return a bare "Restaurant Marburg" or an
 * implausible duration. Apple Maps remains the final source of truth on-device; this keeps
 * obviously vague routes from ever reaching that slower verification step.
 */
export class GeneratedSuggestionValidationError extends Error {}

const budgetLevels = new Set<BudgetLevel>(["guenstig", "mittel", "gehoben"]);
const stationCategories = new Set<StationCategory>([
  "restaurant", "cafe", "bar", "park", "museum", "cinema", "theater", "sight",
  "activity", "shopping", "nature", "nightlife", "other",
]);
const genericPlaceTokens = new Set([
  "restaurant", "cafe", "bar", "park", "museum", "kino", "cinema", "theater",
  "theatre", "spaziergang", "wanderung", "aktivitat", "activity", "ausstellung",
  "sehenswurdigkeit", "nachtleben", "natur", "shopping", "einkaufen", "stadt",
  "innenstadt", "zentrum", "altstadt", "am", "an", "bei", "zum", "zur", "im", "in",
]);

type UnknownRecord = Record<string, unknown>;

interface ValidationOptions {
  /**
   * Models occasionally return a real venue name but omit the city despite the schema prompt.
   * The app always resolves the final place through MapKit, so completing an otherwise specific
   * query with the user's selected city preserves that safety boundary without discarding a
   * useful route.
   */
  appendCityToSpecificHints?: boolean;
  targetDurationMinutes?: number;
}

export function validateGeneratedSuggestions(
  value: unknown,
  city: string,
  options: ValidationOptions = {},
): RawSuggestion[] {
  if (!Array.isArray(value) || value.length !== 5) {
    throw new GeneratedSuggestionValidationError("Die KI hat keine vollständige Auswahl von fünf Optionen geliefert.");
  }

  const seenTitles = new Set<string>();
  return value.map((suggestion, index) => {
    const record = requireRecord(suggestion, `Vorschlag ${index + 1}`);
    const title = requiredText(record.title, "Der Titel eines Vorschlags", 100);
    const titleKey = tokenKey(title);
    if (seenTitles.has(titleKey)) {
      throw new GeneratedSuggestionValidationError("Die KI hat denselben Date-Vorschlag doppelt geliefert.");
    }
    seenTitles.add(titleKey);

    const budget = record.estimatedBudgetLevel;
    if (typeof budget !== "string" || !budgetLevels.has(budget as BudgetLevel)) {
      throw new GeneratedSuggestionValidationError("Die Budgetangabe eines Vorschlags ist ungültig.");
    }

    if (!Array.isArray(record.stations) || record.stations.length < 2 || record.stations.length > 3) {
      throw new GeneratedSuggestionValidationError("Ein Date-Vorschlag braucht zwei oder drei Stopps.");
    }

    const validated = {
      title,
      summary: requiredText(record.summary, "Die Zusammenfassung eines Vorschlags", 280),
      moodTags: textList(record.moodTags, "Die Stimmungen eines Vorschlags", 5, 32),
      estimatedBudgetLevel: budget as BudgetLevel,
      stations: record.stations.map((station, stationIndex) =>
        validateStation(station, city, index + 1, stationIndex + 1, options)),
    };
    if (options.targetDurationMinutes) {
      const total = validated.stations.reduce((sum, station) => sum + station.estimatedDurationMinutes, 0);
      const minimum = Math.max(30, Math.floor(options.targetDurationMinutes * 0.60));
      const maximum = Math.ceil(options.targetDurationMinutes * 1.15);
      if (total < minimum || total > maximum) {
        throw new GeneratedSuggestionValidationError("Die vorgeschlagene Route passt zeitlich nicht zum gewählten Rahmen.");
      }
    }
    return validated;
  }).map((suggestion, _, all) => {
    if (suggestion.stations.length !== all[0].stations.length) {
      throw new GeneratedSuggestionValidationError("Die Optionen haben keine einheitlichen Date-Abschnitte.");
    }
    return suggestion;
  });
}

function validateStation(
  value: unknown,
  city: string,
  suggestionIndex: number,
  stationIndex: number,
  options: ValidationOptions,
): RawStation {
  const record = requireRecord(value, `Stopp ${stationIndex} in Vorschlag ${suggestionIndex}`);
  const category = record.category;
  if (typeof category !== "string" || !stationCategories.has(category as StationCategory)) {
    throw new GeneratedSuggestionValidationError("Ein Stopp hat keine gültige Kategorie.");
  }

  const suppliedHint = requiredText(record.searchQueryHint, "Der Orts-Hinweis", 120);
  const searchQueryHint = options.appendCityToSpecificHints
    ? appendCityToSpecificHint(suppliedHint, city)
    : suppliedHint;
  assertSpecificPlaceHint(searchQueryHint, city);

  const estimatedDurationMinutes = record.estimatedDurationMinutes;
  if (
    typeof estimatedDurationMinutes !== "number"
    || !Number.isInteger(estimatedDurationMinutes)
    || estimatedDurationMinutes < 15
    || estimatedDurationMinutes > 360
  ) {
    throw new GeneratedSuggestionValidationError("Eine Stopp-Dauer muss zwischen 15 und 360 Minuten liegen.");
  }

  return {
    title: requiredText(record.title, "Der Stopp-Titel", 120),
    category: category as StationCategory,
    searchQueryHint,
    description: requiredText(record.description, "Die Stopp-Beschreibung", 280),
    estimatedDurationMinutes,
  };
}

function appendCityToSpecificHint(hint: string, city: string): string {
  const cityTokens = tokens(city).filter((token) => token.length > 2);
  const hintTokens = tokens(hint);
  if (cityTokens.some((token) => hintTokens.includes(token))) return hint;

  // Never turn a generic category such as "Restaurant" into an apparently concrete place.
  // Only named places receive the selected city as a MapKit search qualifier.
  const hasSpecificPlaceToken = hintTokens.some((token) => !genericPlaceTokens.has(token));
  return hasSpecificPlaceToken ? `${hint}, ${city}` : hint;
}

function assertSpecificPlaceHint(searchQueryHint: string, city: string) {
  const cityTokens = tokens(city).filter((token) => token.length > 2);
  const hintTokens = tokens(searchQueryHint);
  if (cityTokens.length === 0 || !cityTokens.some((token) => hintTokens.includes(token))) {
    throw new GeneratedSuggestionValidationError("Ein Orts-Hinweis enthält nicht die angefragte Stadt.");
  }

  const specificTokens = hintTokens.filter((token) => !cityTokens.includes(token) && !genericPlaceTokens.has(token));
  if (specificTokens.length === 0) {
    throw new GeneratedSuggestionValidationError("Die KI hat nur eine Ortsart statt eines konkreten Ortes geliefert.");
  }
}

function textList(value: unknown, fieldName: string, maximumEntries: number, maximumLength: number): string[] {
  if (!Array.isArray(value) || value.length > maximumEntries) {
    throw new GeneratedSuggestionValidationError(`${fieldName} sind ungültig.`);
  }
  return value.map((entry) => requiredText(entry, fieldName, maximumLength));
}

function requiredText(value: unknown, fieldName: string, maximumLength: number): string {
  if (typeof value !== "string") {
    throw new GeneratedSuggestionValidationError(`${fieldName} fehlt.`);
  }
  const cleaned = value.trim().replace(/\s+/g, " ");
  if (cleaned.length === 0 || cleaned.length > maximumLength) {
    throw new GeneratedSuggestionValidationError(`${fieldName} ist ungültig.`);
  }
  return cleaned;
}

function requireRecord(value: unknown, fieldName: string): UnknownRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new GeneratedSuggestionValidationError(`${fieldName} ist ungültig.`);
  }
  return value as UnknownRecord;
}

function tokens(value: string): string[] {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("de-DE")
    .split(/[^\p{L}\p{N}]+/u)
    .filter(Boolean);
}

function tokenKey(value: string): string {
  return tokens(value).join("-");
}
