export type BudgetLevel = "guenstig" | "mittel" | "gehoben";

export type StationCategory =
  | "restaurant" | "cafe" | "bar" | "park" | "museum" | "cinema"
  | "theater" | "sight" | "activity" | "shopping" | "nature" | "nightlife" | "other";

export interface DateStation {
  order: number;
  title: string;
  category: StationCategory;
  searchQueryHint: string;
  description: string;
  estimatedDurationMinutes: number;
  licensedImage?: GeneratedDateImage;
}

export interface GeneratedDateImage {
  url: string;
  sourcePageURL: string;
  creator: string;
  license: string;
  licenseURL: string | null;
  contextLabel: string;
}

export interface DateSuggestion {
  id: string;
  title: string;
  summary: string;
  moodTags: string[];
  estimatedBudgetLevel: BudgetLevel;
  estimatedTotalDurationMinutes: number;
  stations: DateStation[];
}

/** Raw shape returned by Claude's forced tool_choice, before server-side id/order assignment. */
export interface RawStation {
  title: string;
  category: StationCategory;
  searchQueryHint: string;
  description: string;
  estimatedDurationMinutes: number;
}

export interface RawSuggestion {
  title: string;
  summary: string;
  moodTags: string[];
  estimatedBudgetLevel: BudgetLevel;
  stations: RawStation[];
}

/** Matches the DateCriteria value type on the iOS client (Models/DateCriteria.swift). */
export interface DateCriteriaPayload {
  city: string;
  budget: BudgetLevel;
  moods: string[];
  indoorOutdoor: "drinnen" | "draussen" | "egal";
  date: string; // ISO 8601
  time: string; // "HH:mm"
  durationMinutes: number;
  occasion: string;
  dietaryPreferences: string[];
  mobility: "zufuss" | "oepnv" | "auto";
  radiusKm: number;
  planningMode: "date" | "group";
  participantCount: number;
}

export interface GenerateDateSuggestionsRequest {
  /** Exactly one planning owner is required. */
  coupleId?: string;
  matchId?: string;
  ownerUid?: string;
  criteria: DateCriteriaPayload;
}

export interface GenerateDateSuggestionsResponse {
  requestId: string;
  suggestions: DateSuggestion[];
}
