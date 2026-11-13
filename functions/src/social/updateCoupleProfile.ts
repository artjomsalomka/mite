import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { db } from "../firebaseAdmin";
import { normalizeCity, normalizeHandle, optionalText, requireActiveCouple, requireText } from "./socialHelpers";

interface UpdateCoupleProfileRequest {
  displayName: string;
  handle: string;
  bio?: string;
  city?: string;
  avatarPath?: string | null;
}

/**
 * Stores only profile fields that are intentionally public. Private couple data (member names,
 * emails, invite code, dietary preferences, saved dates) remains in its existing collections.
 * A handle-reservation document makes handles unique without making private user documents public.
 */
export const updateCoupleProfile = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const { coupleId } = await requireActiveCouple(request.auth.uid);
  const body = (request.data ?? {}) as Partial<UpdateCoupleProfileRequest>;

  const displayName = requireText(body.displayName, "Profilname", 40);
  const handle = normalizeHandle(body.handle);
  const bio = optionalText(body.bio, "Bio", 160);
  const city = normalizeCity(body.city);
  const avatarPath = validateAvatarPath(body.avatarPath, coupleId);

  const profileRef = db.collection("coupleProfiles").doc(coupleId);
  const newHandleRef = db.collection("profileHandles").doc(handle);

  await db.runTransaction(async (tx) => {
    const currentProfile = await tx.get(profileRef);
    const oldHandle = currentProfile.data()?.handle as string | undefined;

    if (oldHandle !== handle) {
      const handleReservation = await tx.get(newHandleRef);
      if (handleReservation.exists && handleReservation.data()?.coupleId !== coupleId) {
        throw new HttpsError("already-exists", "Dieser Handle ist bereits vergeben.");
      }
      tx.set(newHandleRef, { coupleId, createdAt: Timestamp.now() });
      if (oldHandle) {
        tx.delete(db.collection("profileHandles").doc(oldHandle));
      }
    }

    const now = Timestamp.now();
    tx.set(profileRef, {
      coupleId,
      displayName,
      displayNameNormalized: displayName.toLocaleLowerCase("de-DE"),
      handle,
      bio,
      city,
      cityNormalized: city.toLocaleLowerCase("de-DE"),
      avatarPath,
      createdAt: currentProfile.data()?.createdAt ?? now,
      updatedAt: now,
    }, { merge: true });
  });

  if (avatarPath === null) {
    await getStorage().bucket().file(`profileImages/${coupleId}/avatar.jpg`).delete({ ignoreNotFound: true });
  }

  return { coupleId, handle };
});

function validateAvatarPath(value: unknown, coupleId: string): string | null {
  if (value === undefined || value === null || value === "") {
    return null;
  }
  if (typeof value !== "string" || value !== `profileImages/${coupleId}/avatar.jpg`) {
    throw new HttpsError("invalid-argument", "Ungültiger Avatarpfad.");
  }
  return value;
}
