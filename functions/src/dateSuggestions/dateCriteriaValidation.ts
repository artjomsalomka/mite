import type { DateCriteriaPayload } from "./types";

/** Input boundary for the paid model call. The iOS form only emits this small, controlled
 * vocabulary; validating it again here prevents malformed requests and prompt-shaped free text
 * from being stored or forwarded to OpenAI. */
export class DateCriteriaValidationError extends Error {}

const budgets = new Set<DateCriteriaPayload["budget"]>(["guenstig", "mittel", "gehoben"]);
const moods = new Set(["aktiv", "entspannt", "romantisch", "kulinarisch", "kulturell", "abenteuerlich", "gesellig"]);
const indoorOutdoorOptions = new Set<DateCriteriaPayload["indoorOutdoor"]>(["drinnen", "draussen", "egal"]);
const mobilityOptions = new Set<DateCriteriaPayload["mobility"]>(["zufuss", "oepnv", "auto"]);
const occasions = new Set(["spontanes Date", "Jahrestag", "erstes Date"]);
const allowedDurations = new Set([60, 120, 180, 240]);
const allowedRadii = new Set([2, 5, 10, 20, 35, 50]);
const planningModes = new Set<DateCriteriaPayload["planningMode"]>(["date", "group"]);

type UnknownRecord = Record<string, unknown>;

export function validateDateCriteria(value: unknown): DateCriteriaPayload {
  const record = requireRecord(value);
  const budget = enumValue(record.budget, budgets, "Budget") as DateCriteriaPayload["budget"];
  const indoorOutdoor = enumValue(record.indoorOutdoor, indoorOutdoorOptions, "Drinnen/Draußen") as DateCriteriaPayload["indoorOutdoor"];
  const mobility = enumValue(record.mobility, mobilityOptions, "Mobilität") as DateCriteriaPayload["mobility"];
  const occasion = enumValue(record.occasion, occasions, "Anlass");
  const durationMinutes = allowedNumber(record.durationMinutes, allowedDurations, "Dauer");
  const radiusKm = allowedNumber(record.radiusKm, allowedRadii, "Radius");
  // Existing requests saved by earlier app versions did not have planning context. They remain
  // valid two-person dates; all current clients send the explicit fields below.
  const planningMode = record.planningMode === undefined
    ? "date"
    : enumValue(record.planningMode, planningModes, "Planart") as DateCriteriaPayload["planningMode"];
  const participantCount = record.participantCount === undefined ? 2 : participantNumber(record.participantCount, planningMode);

  return {
    city: cleanCity(record.city),
    budget,
    moods: cleanMoods(record.moods),
    indoorOutdoor,
    date: validISODate(record.date),
    time: validTime(record.time),
    durationMinutes,
    occasion,
    dietaryPreferences: cleanDietaryPreferences(record.dietaryPreferences),
    mobility,
    radiusKm,
    planningMode,
    participantCount,
  };
}

function participantNumber(value: unknown, planningMode: DateCriteriaPayload["planningMode"]): number {
  if (!Number.isInteger(value) || typeof value !== "number") {
    throw new DateCriteriaValidationError("Die Personenzahl ist ungültig.");
  }
  if (planningMode === "date" && value === 2) return value;
  if (planningMode === "group" && value >= 2 && value <= 9) return value;
  throw new DateCriteriaValidationError("Die Personenzahl passt nicht zur Planart.");
}

function cleanCity(value: unknown): string {
  if (typeof value === "string" && /[\r\n\t]/.test(value)) {
    throw new DateCriteriaValidationError("Bitte gib eine Stadt ohne Zeilenumbrüche ein.");
  }
  const city = requiredText(value, "Stadt", 80);
  // This deliberately permits real names such as St. Peter-Ording and Köln, but no newlines,
  // brackets, markup, or arbitrary instructions in a field that becomes part of an LLM prompt.
  if (!/^[\p{L}\p{M}\s.'-]+(?:,\s*[\p{L}\p{M}\s.'-]+)?$/u.test(city)) {
    throw new DateCriteriaValidationError("Bitte gib eine Stadt ohne Sonderzeichen ein.");
  }
  return city;
}

function cleanMoods(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > moods.size || value.some((mood) => typeof mood !== "string" || !moods.has(mood))) {
    throw new DateCriteriaValidationError("Die ausgewählten Stimmungen sind ungültig.");
  }
  if (new Set(value).size !== value.length) {
    throw new DateCriteriaValidationError("Eine Stimmung wurde mehrfach ausgewählt.");
  }
  return [...value] as string[];
}

function cleanDietaryPreferences(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 6) {
    throw new DateCriteriaValidationError("Die Ernährungspräferenzen sind ungültig.");
  }
  return value.map((entry) => requiredText(entry, "Eine Ernährungspräferenz", 40));
}

function validISODate(value: unknown): string {
  const date = requiredText(value, "Datum", 64);
  if (Number.isNaN(Date.parse(date))) {
    throw new DateCriteriaValidationError("Das Datum ist ungültig.");
  }
  return date;
}

function validTime(value: unknown): string {
  const time = requiredText(value, "Uhrzeit", 5);
  if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(time)) {
    throw new DateCriteriaValidationError("Die Uhrzeit muss im Format HH:mm angegeben werden.");
  }
  return time;
}

function allowedNumber(value: unknown, allowedValues: Set<number>, fieldName: string): number {
  if (typeof value !== "number" || !allowedValues.has(value)) {
    throw new DateCriteriaValidationError(`${fieldName} ist ungültig.`);
  }
  return value;
}

function enumValue<T extends string>(value: unknown, allowedValues: Set<T>, fieldName: string): T {
  if (typeof value !== "string" || !allowedValues.has(value as T)) {
    throw new DateCriteriaValidationError(`${fieldName} ist ungültig.`);
  }
  return value as T;
}

function requiredText(value: unknown, fieldName: string, maximumLength: number): string {
  if (typeof value !== "string") {
    throw new DateCriteriaValidationError(`${fieldName} fehlt.`);
  }
  const cleaned = value.trim().replace(/\s+/g, " ");
  if (cleaned.length === 0 || cleaned.length > maximumLength) {
    throw new DateCriteriaValidationError(`${fieldName} ist ungültig.`);
  }
  return cleaned;
}

function requireRecord(value: unknown): UnknownRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new DateCriteriaValidationError("Die Date-Kriterien fehlen.");
  }
  return value as UnknownRecord;
}
