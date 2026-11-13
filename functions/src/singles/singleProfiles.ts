import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { db } from "../firebaseAdmin";
import { age, budget, interests, moods, optionalText, requiredText, requireSingleUser, SingleProfileData } from "./singleHelpers";

interface UpdateSingleProfileRequest {
  displayName: string;
  city: string;
  bio?: string;
  age: number;
  preferredAgeMinimum: number;
  preferredAgeMaximum: number;
  interests: string[];
  budgetPreference: string;
  moods: string[];
  isMatchingActive: boolean;
  avatarPath?: string | null;
}

export const updateSingleProfile = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in required.");
  const uid = request.auth.uid;
  await requireSingleUser(uid);
  const body = (request.data ?? {}) as Partial<UpdateSingleProfileRequest>;

  const displayName = requiredText(body.displayName, "Name", 40);
  const city = requiredText(body.city, "Stadt", 60);
  const profileAge = age(body.age, "Alter");
  const preferredAgeMinimum = age(body.preferredAgeMinimum, "Mindestalter");
  const preferredAgeMaximum = age(body.preferredAgeMaximum, "Höchstalter");
  if (preferredAgeMinimum > preferredAgeMaximum) {
    throw new HttpsError("invalid-argument", "Die Altersspanne ist ungültig.");
  }
  if (typeof body.isMatchingActive !== "boolean") {
    throw new HttpsError("invalid-argument", "Ungültiger Matching-Status.");
  }

  const profileRef = db.collection("singleProfiles").doc(uid);
  const existing = await profileRef.get();
  const avatarPath = validateAvatarPath(body.avatarPath, uid);
  const now = Timestamp.now();
  const profile: SingleProfileData = {
    uid,
    displayName,
    city,
    cityNormalized: city.toLocaleLowerCase("de-DE"),
    bio: optionalText(body.bio, "Bio", 160),
    age: profileAge,
    preferredAgeMinimum,
    preferredAgeMaximum,
    interests: interests(body.interests),
    budgetPreference: budget(body.budgetPreference),
    moods: moods(body.moods),
    isMatchingActive: body.isMatchingActive,
    avatarPath: avatarPath === undefined ? existing.data()?.avatarPath ?? null : avatarPath,
    // Profile edits must never clear a verification result that was issued server-side by the
    // identity provider's signed webhook.
    isVerified: existing.data()?.isVerified === true,
    createdAt: (existing.data()?.createdAt as Timestamp | undefined) ?? now,
    updatedAt: now,
  };
  await profileRef.set(profile);
  if (avatarPath === null) {
    await getStorage().bucket().file(`singleProfileImages/${uid}/avatar.jpg`).delete({ ignoreNotFound: true });
  }
  return { uid };
});

function validateAvatarPath(value: unknown, uid: string): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  const expected = `singleProfileImages/${uid}/avatar.jpg`;
  if (value !== expected) throw new HttpsError("invalid-argument", "Ungültiges Profilbild.");
  return value;
}
