import { createHash } from "node:crypto";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import type { DateSuggestion } from "./types";

type Scope = { coupleId?: string; matchId?: string; ownerUid?: string };
interface ComposeRequest extends Scope {
  requestId?: string;
  candidateIds?: string[];
}

/**
 * Turns one selected option per route segment into the only complete date which can receive
 * paid visuals. The server reads the candidates it generated itself, so a client can never
 * inject arbitrary venues or make image calls for unverified input.
 */
export const composeDateSuggestion = onCall(async (request): Promise<{ suggestion: DateSuggestion }> => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const data = (request.data ?? {}) as ComposeRequest;
  const scopeCount = [data.coupleId, data.matchId, data.ownerUid].filter((value) => typeof value === "string" && value.length > 0).length;
  if (!data.requestId || !Array.isArray(data.candidateIds) || scopeCount !== 1) {
    throw new HttpsError("invalid-argument", "Date-Kontext, Anfrage und Auswahl sind erforderlich.");
  }

  const scopeRef = data.coupleId
    ? db.collection("couples").doc(data.coupleId)
    : data.matchId
      ? db.collection("singleMatches").doc(data.matchId)
      : db.collection("users").doc(data.ownerUid!);
  const scope = await scopeRef.get();
  const hasAccess = data.ownerUid
    ? data.ownerUid === request.auth.uid
    : ((scope.data()?.memberUids ?? []) as string[]).includes(request.auth.uid);
  if (!scope.exists || !hasAccess) {
    throw new HttpsError("permission-denied", "Dieser Date-Vorschlag ist nicht verfügbar.");
  }

  const requestRef = scopeRef.collection("dateRequests").doc(data.requestId);
  const requestSnapshot = await requestRef.get();
  if (!requestSnapshot.exists || requestSnapshot.data()?.status !== "completed") {
    throw new HttpsError("not-found", "Die Date-Auswahl wurde nicht gefunden.");
  }
  const stored = requestSnapshot.data()!;
  const candidates = (stored.suggestions ?? []) as DateSuggestion[];
  const routeCandidates = candidates.filter((item) => /^s[0-4]$/.test(item.id));
  const stationCount = routeCandidates[0]?.stations.length ?? 0;
  if (routeCandidates.length !== 5 || stationCount < 2 || stationCount > 3 || data.candidateIds.length !== stationCount) {
    throw new HttpsError("failed-precondition", "Die Optionen sind nicht vollständig. Bitte erstelle eine neue Auswahl.");
  }

  const stations = data.candidateIds.map((candidateId, order) => {
    const candidate = routeCandidates.find((item) => item.id === candidateId);
    const station = candidate?.stations[order];
    if (!station) throw new HttpsError("invalid-argument", "Eine ausgewählte Option passt nicht zu diesem Abschnitt.");
    // Firestore rejects undefined values. The candidate selection is intentionally text-only,
    // therefore the optional visual field is omitted until generateDateStationImages fills it.
    const { licensedImage: _ignored, ...stationWithoutVisual } = station;
    return { ...stationWithoutVisual, order };
  });
  const normalizedIds = data.candidateIds.join("|");
  const id = "chosen-" + createHash("sha256").update(normalizedIds).digest("hex").slice(0, 14);
  const city = typeof stored.criteria?.city === "string" ? stored.criteria.city : "eurer Stadt";
  const titleParts = stations.map((station) => station.title.replace(/^.*? bei /i, "").replace(/^.*? zum /i, ""));
  const title = titleParts.length === 2
    ? `${titleParts[0]} & ${titleParts[1]}`
    : `${titleParts[0]} · ${titleParts[1]} · ${titleParts[2]}`;
  const suggestion: DateSuggestion = {
    id,
    title: title.slice(0, 100),
    summary: `Eure Auswahl für ${city}: ${stations.map((station) => station.title).join(" → ")}. Alles ist in einem Ablauf für euch verbunden.`,
    moodTags: Array.from(new Set(routeCandidates.flatMap((item) => item.moodTags))).slice(0, 5),
    estimatedBudgetLevel: routeCandidates[0].estimatedBudgetLevel,
    estimatedTotalDurationMinutes: stations.reduce((total, station) => total + station.estimatedDurationMinutes, 0),
    stations,
  };
  const updated = candidates.some((item) => item.id === id)
    ? candidates.map((item) => item.id === id ? suggestion : item)
    : [...candidates, suggestion];
  await requestRef.update({ suggestions: updated, composedAt: Timestamp.now() });
  return { suggestion };
});
