import { HttpsError } from "firebase-functions/v2/https";
import { db } from "../firebaseAdmin";

export interface ActiveCoupleContext {
  coupleId: string;
  memberUids: string[];
}

/** Returns an active couple when one exists, without making pairing a prerequisite for social use. */
export async function optionalActiveCouple(uid: string): Promise<ActiveCoupleContext | null> {
  const userSnap = await db.collection("users").doc(uid).get();
  const coupleId = userSnap.data()?.coupleId as string | undefined;
  if (!coupleId) return null;

  const coupleSnap = await db.collection("couples").doc(coupleId).get();
  const coupleData = coupleSnap.data();
  const memberUids = (coupleData?.memberUids ?? []) as string[];
  if (!coupleSnap.exists || coupleData?.status !== "active" || !memberUids.includes(uid)) return null;
  return { coupleId, memberUids };
}

/** Resolves the caller's couple once, then verifies the couple is active and still contains them. */
export async function requireActiveCouple(uid: string): Promise<ActiveCoupleContext> {
  const context = await optionalActiveCouple(uid);
  if (!context) {
    throw new HttpsError("failed-precondition", "Du bist noch keinem aktiven Paar zugeordnet.");
  }
  return context;
}

export function requireText(value: unknown, field: string, maxLength: number, allowEmpty = false): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} muss Text sein.`);
  }
  const normalized = value.trim().replace(/\s+/g, " ");
  if ((!allowEmpty && normalized.length === 0) || normalized.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} ist ungültig.`);
  }
  return normalized;
}

export function optionalText(value: unknown, field: string, maxLength: number): string {
  if (value === undefined || value === null) {
    return "";
  }
  return requireText(value, field, maxLength, true);
}

export function normalizeHandle(value: unknown): string {
  const handle = requireText(value, "Handle", 24).toLowerCase();
  if (!/^[a-z0-9][a-z0-9._]{2,23}$/.test(handle)) {
    throw new HttpsError("invalid-argument", "Der Handle darf nur Kleinbuchstaben, Zahlen, Punkte und Unterstriche enthalten.");
  }
  return handle;
}

export function normalizeCity(value: unknown): string {
  return optionalText(value, "Stadt", 60);
}

export function normalizeCategories(value: unknown): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value) || value.length > 4) {
    throw new HttpsError("invalid-argument", "Bitte höchstens vier Kategorien wählen.");
  }
  return [...new Set(value.map((entry) => requireText(entry, "Kategorie", 24)))];
}
