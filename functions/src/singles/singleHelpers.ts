import { HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../firebaseAdmin";

export interface SingleProfileData {
  uid: string;
  displayName: string;
  city: string;
  cityNormalized: string;
  bio: string;
  age: number;
  preferredAgeMinimum: number;
  preferredAgeMaximum: number;
  interests: string[];
  budgetPreference: "guenstig" | "mittel" | "gehoben";
  moods: string[];
  isMatchingActive: boolean;
  avatarPath?: string | null;
  isVerified?: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

const validBudgets = new Set(["guenstig", "mittel", "gehoben"]);
const validMoods = new Set(["aktiv", "entspannt", "romantisch", "kulinarisch", "kulturell", "abenteuerlich"]);

export async function requireSingleUser(uid: string): Promise<void> {
  const user = await db.collection("users").doc(uid).get();
  const data = user.data();
  // Couple membership always disables matching, including for older accounts that may still
  // carry the legacy `accountMode: single` value from before they connected as a pair.
  if (!user.exists || data?.accountMode !== "single" || data?.datingEnabled === false || data?.coupleId) {
    throw new HttpsError("failed-precondition", "Dieser Bereich ist nur für Single-Profile verfügbar.");
  }
}

export async function requireSingleProfile(uid: string): Promise<SingleProfileData> {
  await requireSingleUser(uid);
  const profile = await db.collection("singleProfiles").doc(uid).get();
  if (!profile.exists) {
    throw new HttpsError("failed-precondition", "Bitte vervollständige zuerst dein Single-Profil.");
  }
  return profile.data() as SingleProfileData;
}

export function requiredText(value: unknown, label: string, maximumLength: number): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${label} muss Text sein.`);
  }
  const normalized = value.trim().replace(/\s+/g, " ");
  if (!normalized || normalized.length > maximumLength) {
    throw new HttpsError("invalid-argument", `${label} ist ungültig.`);
  }
  return normalized;
}

export function optionalText(value: unknown, label: string, maximumLength: number): string {
  if (value === undefined || value === null) return "";
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${label} muss Text sein.`);
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length > maximumLength) throw new HttpsError("invalid-argument", `${label} ist zu lang.`);
  return normalized;
}

export function age(value: unknown, label: string): number {
  if (!Number.isInteger(value) || (value as number) < 18 || (value as number) > 99) {
    throw new HttpsError("invalid-argument", `${label} muss zwischen 18 und 99 liegen.`);
  }
  return value as number;
}

export function interests(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 8) {
    throw new HttpsError("invalid-argument", "Bitte wähle höchstens acht Interessen.");
  }
  return [...new Set(value.map((entry) => requiredText(entry, "Interesse", 24)))];
}

export function budget(value: unknown): SingleProfileData["budgetPreference"] {
  if (typeof value !== "string" || !validBudgets.has(value)) {
    throw new HttpsError("invalid-argument", "Ungültige Budget-Präferenz.");
  }
  return value as SingleProfileData["budgetPreference"];
}

export function moods(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 3 || !value.every((mood) => typeof mood === "string" && validMoods.has(mood))) {
    throw new HttpsError("invalid-argument", "Bitte wähle ein bis drei Stimmungen.");
  }
  return [...new Set(value as string[])];
}

export function suggestion(profile: SingleProfileData, commonInterestCount: number) {
  return {
    uid: profile.uid,
    displayName: profile.displayName,
    city: profile.city,
    bio: profile.bio,
    age: profile.age,
    interests: profile.interests,
    budgetPreference: profile.budgetPreference,
    moods: profile.moods,
    isVerified: profile.isVerified === true,
    avatarPath: profile.avatarPath ?? null,
    commonInterestCount,
  };
}

export function relationshipId(fromUid: string, toUid: string): string {
  return `${fromUid}_${toUid}`;
}

export function matchId(firstUid: string, secondUid: string): string {
  return [firstUid, secondUid].sort().join("_");
}
