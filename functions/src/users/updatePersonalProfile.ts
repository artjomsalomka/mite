import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { db } from "../firebaseAdmin";
import {
  cleanPersonalDisplayName,
  PersonalProfileValidationError,
  validatePersonalAvatarPath,
} from "./personalProfileValidation";
import { ensurePersonProfile } from "../social/personProfiles";

interface UpdatePersonalProfileRequest {
  displayName: string;
  avatarPath?: string | null;
}

/**
 * Updates the private identity of the current person. If they are connected as a couple, the
 * couple's denormalized member snapshot is refreshed in the same transaction. This preserves
 * the fast avatar stack without granting the client write access to couples/{coupleId}.
 */
export const updatePersonalProfile = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const uid = request.auth.uid;
  const body = (request.data ?? {}) as Partial<UpdatePersonalProfileRequest>;
  let displayName: string;
  let avatarPath: string | null;
  try {
    displayName = cleanPersonalDisplayName(body.displayName);
    avatarPath = validatePersonalAvatarPath(body.avatarPath, uid);
  } catch (error) {
    if (error instanceof PersonalProfileValidationError) {
      throw new HttpsError("invalid-argument", error.message);
    }
    throw error;
  }
  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (tx) => {
    const user = await tx.get(userRef);
    if (!user.exists) {
      throw new HttpsError("failed-precondition", "Kein Nutzerprofil gefunden.");
    }

    const now = Timestamp.now();
    const coupleId = user.data()?.coupleId;
    tx.update(userRef, { displayName, avatarPath, updatedAt: now });

    if (typeof coupleId !== "string" || coupleId.length === 0) return;

    const coupleRef = db.collection("couples").doc(coupleId);
    const couple = await tx.get(coupleRef);
    if (!couple.exists || !(couple.data()?.memberUids ?? []).includes(uid)) {
      throw new HttpsError("failed-precondition", "Die Paarverbindung konnte nicht bestätigt werden.");
    }

    const members = (couple.data()?.members ?? []) as Array<Record<string, unknown>>;
    const patchedMembers = members.map((member) => member.uid === uid
      ? { ...member, displayName, avatarPath }
      : member);
    if (!members.some((member) => member.uid === uid)) {
      throw new HttpsError("failed-precondition", "Dein Paarprofil ist unvollständig.");
    }
    tx.update(coupleRef, { members: patchedMembers, updatedAt: now });
  });

  // Keep the public identity's name in step only if a person has elected to create one. The
  // helper itself keeps discoverability off by default, so this never turns a private user into
  // a searchable profile as a side effect of editing their personal account.
  await ensurePersonProfile(uid);

  if (avatarPath === null) {
    await getStorage().bucket().file(`userImages/${uid}/avatar.jpg`).delete({ ignoreNotFound: true });
  }

  return { displayName, avatarPath };
});
