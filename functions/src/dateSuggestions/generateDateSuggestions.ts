import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret, defineString } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { buildSystemPrompt, buildUserContent, RatingHistoryEntry } from "./buildPrompt";
import { callOpenAI } from "./openaiClient";
import { validateGeneratedSuggestions } from "./generatedSuggestionValidation";
import { DateCriteriaValidationError, validateDateCriteria } from "./dateCriteriaValidation";
import { DateGenerationRateLimitState, nextDateGenerationRateLimit } from "./dateGenerationRateLimit";
import type { DateCriteriaPayload, DateSuggestion, GenerateDateSuggestionsRequest, GenerateDateSuggestionsResponse } from "./types";

const openaiApiKey = defineSecret("OPENAI_API_KEY");
// Configurable so the model can be swapped without a code change. gpt-5.6-terra is the
// cost/quality balance point (per-token roughly between Luna and Sol) — see the model
// comparison discussion for why this replaced claude-sonnet-5 here.
const openaiModel = defineString("OPENAI_MODEL", { default: "gpt-5.6-terra" });

export const generateDateSuggestions = onCall(
  { secrets: [openaiApiKey] },
  async (request): Promise<GenerateDateSuggestionsResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in required.");
    }
    const uid = request.auth.uid;
    const { coupleId, matchId, ownerUid, criteria: unvalidatedCriteria } = (request.data ?? {}) as Partial<GenerateDateSuggestionsRequest>;
    const scopeCount = [coupleId, matchId, ownerUid].filter((value) => typeof value === "string" && value.length > 0).length;
    if (!unvalidatedCriteria || scopeCount !== 1) {
      throw new HttpsError("invalid-argument", "Genau ein Date-Kontext und Kriterien sind erforderlich.");
    }
    let criteria: DateCriteriaPayload;
    try {
      criteria = validateDateCriteria(unvalidatedCriteria);
    } catch (error) {
      if (error instanceof DateCriteriaValidationError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }

    const isFirstMeeting = Boolean(matchId);
    const scopeRef = coupleId
      ? db.collection("couples").doc(coupleId)
      : matchId
        ? db.collection("singleMatches").doc(matchId)
        : db.collection("users").doc(ownerUid!);
    const scopeSnap = await scopeRef.get();
    if (!scopeSnap.exists) {
      throw new HttpsError("not-found", isFirstMeeting ? "Match nicht gefunden." : "Paar nicht gefunden.");
    }
    const memberUids = ownerUid ? [ownerUid] : (scopeSnap.data()!.memberUids ?? []) as string[];
    const isActiveMatch = !isFirstMeeting || scopeSnap.data()!.status === "matched";
    if (!memberUids.includes(uid) || !isActiveMatch) {
      throw new HttpsError("permission-denied", isFirstMeeting ? "Dieses Match ist nicht verfügbar." : "Dieser Planungsbereich ist nicht verfügbar.");
    }

    await reserveGenerationSlot(uid);

    const ratingHistory = await fetchRecentRatings(scopeRef.collection("savedDates"));

    const systemPrompt = buildSystemPrompt(isFirstMeeting, criteria.planningMode);
    const userContent = buildUserContent(criteria, ratingHistory, isFirstMeeting);

    let rawSuggestions;
    try {
      const raw = await callOpenAI(systemPrompt, userContent, openaiModel.value(), openaiApiKey.value());
      rawSuggestions = validateGeneratedSuggestions(raw.suggestions, criteria.city, {
        appendCityToSpecificHints: true,
        targetDurationMinutes: criteria.durationMinutes,
      });
    } catch (error) {
      // Keep diagnostics useful without persisting prompts, credentials, or provider payloads.
      logger.warn("Date suggestion generation failed.", {
        failureType: error instanceof Error ? error.name : "UnknownError",
        providerStatus: typeof (error as { status?: unknown })?.status === "number"
          ? (error as { status: number }).status
          : undefined,
      });
      const requestRef = scopeRef.collection("dateRequests").doc();
      await requestRef.set({
        criteria,
        requestedByUid: uid,
        createdAt: Timestamp.now(),
        status: "failed",
        suggestions: [],
        errorMessage: error instanceof Error ? error.message : "Unbekannter Fehler",
      });
      throw new HttpsError(
        "unavailable",
        "Die KI konnte gerade keine vollständige Route erstellen. Bitte versuche es erneut.",
      );
    }

    const suggestions: DateSuggestion[] = rawSuggestions.map((suggestion, suggestionIndex) => ({
      id: `s${suggestionIndex}`,
      title: suggestion.title,
      summary: suggestion.summary,
      moodTags: suggestion.moodTags,
      estimatedBudgetLevel: suggestion.estimatedBudgetLevel,
      estimatedTotalDurationMinutes: suggestion.stations.reduce((sum, s) => sum + s.estimatedDurationMinutes, 0),
      stations: suggestion.stations.map((station, stationIndex) => ({
        order: stationIndex,
        title: station.title,
        category: station.category,
        searchQueryHint: station.searchQueryHint,
        description: station.description,
        estimatedDurationMinutes: station.estimatedDurationMinutes,
      })),
    }));

    const requestRef = scopeRef.collection("dateRequests").doc();
    await requestRef.set({
      criteria,
      requestedByUid: uid,
      createdAt: Timestamp.now(),
      status: "completed",
      suggestions,
      errorMessage: null,
    });

    return { requestId: requestRef.id, suggestions };
  }
);

async function fetchRecentRatings(savedDates: FirebaseFirestore.CollectionReference): Promise<RatingHistoryEntry[]> {
  // Deliberately NOT `.where("rating", "!=", null).orderBy("rating.ratedAt", "desc")` — that
  // shape (inequality filter + orderBy on a different, nested field) demands a composite index
  // whose exact required shape Firestore's query planner and its own "create this index" error
  // disagreed on in practice (confirmed live: two differently-shaped composite indexes both
  // reported READY, yet the query kept failing with the identical "requires an index" error).
  // A couple's savedDates collection is small, so ordering by `scheduledAt` (already a plain,
  // unindexed-by-default-safe single-field query) and filtering for a rating client-side is a
  // simpler, more robust trade — a little over-fetching instead of a fragile index dependency.
  const snap = await savedDates
    .orderBy("scheduledAt", "desc")
    .limit(20)
    .get();

  type RatingField = { stars: number; tags?: string[]; comment?: string | null; ratedAt?: FirebaseFirestore.Timestamp };

  return snap.docs
    .map((doc) => doc.data())
    .filter((data) => data.rating != null)
    .sort((a, b) => {
      const aRating = a.rating as RatingField;
      const bRating = b.rating as RatingField;
      return (bRating.ratedAt?.toMillis() ?? 0) - (aRating.ratedAt?.toMillis() ?? 0);
    })
    .slice(0, 5)
    .map((data) => {
      const rating = data.rating as RatingField;
      return {
        title: data.title as string,
        stars: rating.stars,
        tags: rating.tags ?? [],
        comment: rating.comment ?? null,
      };
    });
}

async function reserveGenerationSlot(uid: string) {
  const rateLimitRef = db.collection("users").doc(uid).collection("dateGenerationRateLimits").doc("current");
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(rateLimitRef);
    const stored = snapshot.data();
    const state: DateGenerationRateLimitState | undefined = stored?.windowStartedAt instanceof Timestamp
      && stored?.lastRequestedAt instanceof Timestamp
      && typeof stored.requestsInWindow === "number"
      ? {
          windowStartedAtMilliseconds: stored.windowStartedAt.toMillis(),
          requestsInWindow: stored.requestsInWindow,
          lastRequestedAtMilliseconds: stored.lastRequestedAt.toMillis(),
        }
      : undefined;
    const now = Timestamp.now();
    const decision = nextDateGenerationRateLimit(state, now.toMillis());
    if (!decision.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        decision.reason === "too_fast"
          ? "Bitte warte kurz, bevor du neue Vorschläge generierst."
          : "Du hast gerade viele Date-Ideen generiert. Bitte versuche es in einigen Minuten erneut.",
      );
    }
    transaction.set(rateLimitRef, {
      windowStartedAt: Timestamp.fromMillis(decision.nextState.windowStartedAtMilliseconds),
      requestsInWindow: decision.nextState.requestsInWindow,
      lastRequestedAt: now,
    });
  });
}
