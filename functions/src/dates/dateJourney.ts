import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";
import { updatedStationProgress } from "./journeyValidation";

export const setDateStationCompleted = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Bitte anmelden.");
  const { scopeType, scopeId, dateId, stationOrder, completed } = request.data ?? {};
  if (!["couple", "match", "personal"].includes(scopeType) || ![scopeId, dateId].every((id) => typeof id === "string" && /^[\w-]{1,160}$/.test(id))) {
    throw new HttpsError("invalid-argument", "Ungültiger Date-Plan.");
  }
  const scopeRef = db.collection(scopeType === "personal" ? "users" : scopeType === "couple" ? "couples" : "singleMatches").doc(scopeId);
  const dateRef = scopeRef.collection("savedDates").doc(dateId);
  return db.runTransaction(async (tx) => {
    const [scope, date] = await Promise.all([tx.get(scopeRef), tx.get(dateRef)]);
    const hasAccess = scope.exists && (scopeType === "personal"
      ? scopeId === request.auth!.uid
      : scope.data()?.memberUids?.includes(request.auth!.uid)
        && scope.data()?.status === (scopeType === "couple" ? "active" : "matched"));
    if (!hasAccess) {
      throw new HttpsError("permission-denied", "Dieser Date-Plan ist nicht verfügbar.");
    }
    const plan = date.data();
    if (!plan) throw new HttpsError("not-found", "Dieses Date wurde nicht gefunden.");
    if (plan.status !== "upcoming" || !(plan.scheduledAt instanceof Timestamp) || plan.scheduledAt.toMillis() > Date.now()) {
      throw new HttpsError("failed-precondition", "Ihr könnt Stationen abhaken, sobald euer Date beginnt.");
    }
    let progress: number[];
    try {
      progress = updatedStationProgress((plan.stations ?? []).map((station: { order: number }) => station.order),
        plan.completedStationOrders ?? [], stationOrder, completed);
    } catch {
      throw new HttpsError("invalid-argument", "Diese Station gehört nicht zu eurem Date.");
    }
    tx.update(dateRef, { completedStationOrders: progress });
    return { completedStationOrders: progress };
  });
});
